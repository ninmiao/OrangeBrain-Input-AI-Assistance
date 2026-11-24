// SPDX-License-Identifier: GPL-3.0-or-later
import OCRime
import UIKit

/// The whole keyboard: composition row, candidate bar and the key area. It is a plain
/// UIView so that the extension and the test host (as a text view's inputView) share it.
public final class KeyboardView: UIView {
    public let controller: KeyboardController

    /// Our own globe key is drawn only when the system asks for one
    /// (`UIInputViewController.needsInputModeSwitchKey`). Target / action of that key
    /// are set by the view controller (`handleInputModeList(from:with:)`).
    public var showsGlobeKey = false { didSet { if showsGlobeKey != oldValue { reloadLayoutIfNeeded() } } }
    public var returnKind: ReturnKeyKind = .standard { didSet { if returnKind != oldValue { reloadLayoutIfNeeded() } } }
    public var globeTarget: AnyObject?
    public var globeAction: Selector?
    /// Haptics need Full Access in a keyboard extension.
    public var hapticsEnabled = false

    private let compositionLabel = UILabel()
    private let separator = UIView()
    private let candidateLayout = UICollectionViewFlowLayout()
    private lazy var candidateView = UICollectionView(frame: .zero, collectionViewLayout: candidateLayout)
    private var keyButtons: [KeyButton] = []
    private var renderedLayout: KeyboardLayout?
    private var rows: [[RowItem]] = []
    private var candidates: [RimeCandidate] = []
    private var highlighted = 0
    private var popup: UILabel?
    private var deleteTimer: Timer?
    private let impact = UIImpactFeedbackGenerator(style: .light)

    // MARK: sizes

    struct Metrics {
        let top: CGFloat, composition: CGFloat, candidates: CGFloat, keysGap: CGFloat
        let keyHeight: CGFloat, rowGap: CGFloat, keyGap: CGFloat, side: CGFloat, bottom: CGFloat
        var height: CGFloat { top + composition + candidates + keysGap + 4 * keyHeight + 3 * rowGap + bottom }
    }

    static func metrics(landscape: Bool) -> Metrics {
        landscape
            ? Metrics(top: 3, composition: 14, candidates: 32, keysGap: 4, keyHeight: 34, rowGap: 6, keyGap: 5, side: 4, bottom: 4)
            : Metrics(top: 4, composition: 18, candidates: 40, keysGap: 6, keyHeight: 44, rowGap: 10, keyGap: 6, side: 3, bottom: 8)
    }

    public static func preferredHeight(landscape: Bool) -> CGFloat {
        metrics(landscape: landscape).height
    }

    private var isLandscape: Bool { traitCollection.verticalSizeClass == .compact }

    // MARK: setup

    public init(controller: KeyboardController) {
        self.controller = controller
        super.init(frame: CGRect(x: 0, y: 0, width: 390, height: Self.preferredHeight(landscape: false)))
        backgroundColor = KeyboardTheme.background
        autoresizingMask = [.flexibleWidth]
        accessibilityIdentifier = "oc.keyboard"

        compositionLabel.font = KeyboardTheme.compositionFont
        compositionLabel.textColor = KeyboardTheme.secondaryText
        compositionLabel.accessibilityIdentifier = "oc.composition"
        addSubview(compositionLabel)

        candidateLayout.scrollDirection = .horizontal
        candidateLayout.minimumLineSpacing = 0
        candidateLayout.minimumInteritemSpacing = 0
        candidateLayout.sectionInset = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        candidateView.backgroundColor = .clear
        candidateView.showsHorizontalScrollIndicator = false
        candidateView.dataSource = self
        candidateView.delegate = self
        candidateView.register(CandidateCell.self, forCellWithReuseIdentifier: CandidateCell.reuseIdentifier)
        candidateView.accessibilityIdentifier = "oc.candidates"
        addSubview(candidateView)

        separator.backgroundColor = KeyboardTheme.separator
        addSubview(separator)

        controller.onChange = { [weak self] state in self?.render(state) }
        render(controller.state)
    }

    public required init?(coder: NSCoder) { fatalError("not used") }

    deinit { deleteTimer?.invalidate() }

    // MARK: rendering

    private func currentLayout() -> KeyboardLayout {
        let state = controller.state
        return KeyboardLayout(panel: state.panel, mode: state.mode, shift: state.shift,
                              returnKind: returnKind, showGlobe: showsGlobeKey)
    }

    private func render(_ state: KeyboardState) {
        let text = state.isComposing ? state.composition : (state.notice ?? "")
        compositionLabel.text = text
        compositionLabel.accessibilityLabel = state.isComposing ? state.composition : nil
        let candidatesChanged = state.candidates != candidates
        let highlightChanged = state.highlighted != highlighted
        candidates = state.candidates
        highlighted = state.highlighted
        if candidatesChanged {
            candidateView.reloadData()
            candidateView.setContentOffset(.zero, animated: false)
        } else if highlightChanged {
            candidateView.reloadData()
        }
        reloadLayoutIfNeeded()
    }

    private func reloadLayoutIfNeeded() {
        let layout = currentLayout()
        if let old = renderedLayout, old.panel == layout.panel, old.mode == layout.mode, old.shift == layout.shift,
           old.returnKind == layout.returnKind, old.showGlobe == layout.showGlobe { return }
        renderedLayout = layout
        rows = layout.rows
        keyButtons.forEach { $0.removeFromSuperview() }
        keyButtons = []
        for row in rows {
            for item in row {
                guard case .key(let spec) = item else { continue }
                let button = KeyButton(spec: spec)
                wire(button)
                addSubview(button)
                keyButtons.append(button)
            }
        }
        setNeedsLayout()
    }

    private func wire(_ button: KeyButton) {
        let spec = button.spec
        button.onTouchDown = { [weak self] key in self?.touchDown(key) }
        button.onTouchUp = { [weak self] key in self?.touchUp(key) }
        switch spec.action {
        case .delete:
            break   // acts on touch down and repeats while held
        case .globe:
            if let target = globeTarget, let action = globeAction {
                button.addTarget(target, action: action, for: .allTouchEvents)
            }
        default:
            button.onTap = { [weak self] key in self?.controller.handle(key.spec.action) }
        }
    }

    // MARK: feedback

    private func touchDown(_ key: KeyButton) {
        if hapticsEnabled { impact.impactOccurred() }
        switch key.spec.action {
        case .delete:
            controller.handle(.delete)
            startDeleteRepeat()
        case .character(let text) where controller.state.panel == .letters && text.count == 1:
            showPopup(for: key, text: text)
        default:
            break
        }
    }

    private func touchUp(_ key: KeyButton) {
        if key.spec.action == .delete { stopDeleteRepeat() }
        hidePopup()
    }

    private func startDeleteRepeat() {
        stopDeleteRepeat()
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            self?.repeatDelete()
        }
    }

    private func repeatDelete() {
        controller.handle(.delete)
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: false) { [weak self] _ in
            self?.repeatDelete()
        }
    }

    private func stopDeleteRepeat() {
        deleteTimer?.invalidate()
        deleteTimer = nil
    }

    private func showPopup(for key: KeyButton, text: String) {
        hidePopup()
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 34)
        label.textColor = KeyboardTheme.text
        label.textAlignment = .center
        label.backgroundColor = KeyboardTheme.key
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        let width = key.frame.width + 18
        var x = key.frame.midX - width / 2
        x = max(2, min(bounds.width - width - 2, x))
        label.frame = CGRect(x: x, y: max(0, key.frame.minY - 54), width: width, height: 52)
        label.isAccessibilityElement = false
        addSubview(label)
        popup = label
    }

    private func hidePopup() {
        popup?.removeFromSuperview()
        popup = nil
    }

    // MARK: layout

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.preferredHeight(landscape: isLandscape))
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let m = Self.metrics(landscape: isLandscape)
        let width = bounds.width
        compositionLabel.frame = CGRect(x: 12, y: m.top, width: width - 24, height: m.composition)
        let candidateTop = m.top + m.composition
        candidateView.frame = CGRect(x: 0, y: candidateTop, width: width, height: m.candidates)
        separator.frame = CGRect(x: 0, y: candidateTop + m.candidates, width: width, height: 1 / UIScreen.main.scale)

        var y = candidateTop + m.candidates + m.keysGap
        var buttonIndex = 0
        for row in rows {
            let totalWeight = row.reduce(0) { $0 + $1.weight }
            let gaps = CGFloat(max(row.count - 1, 0)) * m.keyGap
            let unit = (width - 2 * m.side - gaps) / totalWeight
            var x = m.side
            for item in row {
                let itemWidth = unit * item.weight
                if case .key = item {
                    keyButtons[buttonIndex].frame = CGRect(x: x, y: y, width: itemWidth, height: m.keyHeight).integral
                    buttonIndex += 1
                }
                x += itemWidth + m.keyGap
            }
            y += m.keyHeight + m.rowGap
        }
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.verticalSizeClass != traitCollection.verticalSizeClass { invalidateIntrinsicContentSize() }
        candidateView.reloadData()
    }
}

// MARK: candidate bar

extension KeyboardView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        candidates.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CandidateCell.reuseIdentifier, for: indexPath)
        if let cell = cell as? CandidateCell {
            cell.configure(candidates[indexPath.item], highlighted: indexPath.item == highlighted, index: indexPath.item)
        }
        return cell
    }

    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                               sizeForItemAt indexPath: IndexPath) -> CGSize {
        CGSize(width: CandidateCell.width(for: candidates[indexPath.item]), height: collectionView.bounds.height)
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if hapticsEnabled { impact.impactOccurred() }
        controller.selectCandidate(at: indexPath.item)
    }
}

final class CandidateCell: UICollectionViewCell {
    static let reuseIdentifier = "candidate"
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 6
        contentView.layer.cornerCurve = .continuous
        label.textAlignment = .center
        contentView.addSubview(label)
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
    }

    static func attributed(_ candidate: RimeCandidate) -> NSAttributedString {
        let result = NSMutableAttributedString(string: candidate.text, attributes: [
            .font: KeyboardTheme.candidateFont, .foregroundColor: KeyboardTheme.text,
        ])
        if !candidate.comment.isEmpty {
            result.append(NSAttributedString(string: " " + candidate.comment, attributes: [
                .font: KeyboardTheme.commentFont, .foregroundColor: KeyboardTheme.secondaryText,
            ]))
        }
        return result
    }

    static func width(for candidate: RimeCandidate) -> CGFloat {
        ceil(attributed(candidate).size().width) + 22
    }

    func configure(_ candidate: RimeCandidate, highlighted: Bool, index: Int) {
        label.attributedText = Self.attributed(candidate)
        contentView.backgroundColor = highlighted ? KeyboardTheme.candidateHighlight : .clear
        accessibilityIdentifier = "oc.candidate.\(index)"
        accessibilityLabel = candidate.text
        accessibilityTraits = highlighted ? [.button, .selected] : .button
    }
}
