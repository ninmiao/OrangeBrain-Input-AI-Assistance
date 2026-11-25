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
    /// The 1-0 row above qwerty (setting in the app, on by default).
    public var numberRowEnabled = true {
        didSet {
            guard numberRowEnabled != oldValue else { return }
            reloadLayoutIfNeeded()
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }
    public var returnKind: ReturnKeyKind = .standard { didSet { if returnKind != oldValue { reloadLayoutIfNeeded() } } }
    public weak var globeTarget: AnyObject?
    public var globeAction: Selector?
    /// Haptics need Full Access in a keyboard extension.
    public var hapticsEnabled = false { didSet { if hapticsEnabled { impact.prepare() } } }

    private let compositionLabel = UILabel()
    private let separator = UIView()
    private let aiBar = AiBarView()
    private let expandButton = UIButton(type: .system)
    /// Created when first needed: a hidden collection view and text view still cost memory in the keyboard process.
    private var gridView: CandidateGridView?
    private var textPanel: AiTextPanel?
    private var gridOpen = false
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
        let top: CGFloat, composition: CGFloat, candidates: CGFloat, aiBar: CGFloat, keysGap: CGFloat
        let keyHeight: CGFloat, rowGap: CGFloat, keyGap: CGFloat, side: CGFloat, bottom: CGFloat
        /// Height with `rows` key rows (5 with the number row on the letters panel, otherwise 4).
        func height(rows: Int) -> CGFloat {
            top + composition + candidates + aiBar + keysGap + CGFloat(rows) * keyHeight + CGFloat(rows - 1) * rowGap + bottom
        }
        /// Where the first key row starts.
        var keysTop: CGFloat { top + composition + candidates + aiBar + keysGap }
        var expandWidth: CGFloat { 34 }
    }

    static func metrics(landscape: Bool) -> Metrics {
        landscape
            ? Metrics(top: 3, composition: 12, candidates: 28, aiBar: 24, keysGap: 3, keyHeight: 30, rowGap: 4, keyGap: 5, side: 4, bottom: 3)
            : Metrics(top: 4, composition: 18, candidates: 40, aiBar: 30, keysGap: 6, keyHeight: 40, rowGap: 8, keyGap: 6, side: 3, bottom: 8)
    }

    /// The keyboard has one height in every panel: the one with the number row (when it is on) or
    /// without it; panels with fewer rows get taller keys.
    public static func preferredHeight(landscape: Bool, numberRow: Bool = true) -> CGFloat {
        metrics(landscape: landscape).height(rows: numberRow ? 5 : 4)
    }

    private var isLandscape: Bool { traitCollection.verticalSizeClass == .compact }

    // MARK: setup

    public init(controller: KeyboardController) {
        self.controller = controller
        super.init(frame: CGRect(x: 0, y: 0, width: 390, height: Self.preferredHeight(landscape: false)))
        clipsToBounds = true
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

        addSubview(aiBar)
        aiBar.onItem = { [weak controller] index in controller?.aiItemTapped(index) }
        aiBar.onAssistant = { [weak controller] in controller?.aiAssistantTapped() }
        aiBar.onEmoji = { [weak controller] in controller?.aiEmojiTapped() }
        aiBar.onCancel = { [weak controller] in controller?.aiCancelTapped() }

        let chevron = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        expandButton.setImage(UIImage(systemName: "chevron.down", withConfiguration: chevron), for: .normal)
        expandButton.tintColor = KeyboardTheme.secondaryText
        expandButton.accessibilityIdentifier = "oc.expand"
        expandButton.accessibilityLabel = "展开候选"
        expandButton.addTarget(self, action: #selector(toggleGrid), for: .touchUpInside)
        expandButton.isHidden = true
        addSubview(expandButton)


        controller.onChange = { [weak self] state in self?.render(state) }
        render(controller.state)
    }

    public required init?(coder: NSCoder) { fatalError("not used") }

    deinit { deleteTimer?.invalidate() }

    // MARK: rendering

    private func currentLayout() -> KeyboardLayout {
        let state = controller.state
        return KeyboardLayout(panel: state.panel, mode: state.mode, shift: state.shift,
                              returnKind: returnKind, showGlobe: showsGlobeKey, numberRow: numberRowEnabled)
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
            gridView?.candidates = candidates
        } else if highlightChanged {
            candidateView.reloadData()
        }
        // The expand key exists while there are candidates; the grid closes with them.
        expandButton.isHidden = candidates.isEmpty
        if candidates.isEmpty && gridOpen { closeGrid() }
        aiBar.apply(state.ai)
        if gridOpen { gridView?.candidates = state.moreCandidates ?? candidates }
        if let index = state.ai.expandedIndex, state.ai.items.indices.contains(index) {
            presentTextPanel().show(item: state.ai.items[index], index: index)
        } else {
            textPanel?.isHidden = true
        }
        reloadLayoutIfNeeded()
        setNeedsLayout()
    }

    @objc private func toggleGrid() {
        feedback()
        if gridOpen { closeGrid() } else { openGrid() }
    }

    private func presentGrid() -> CandidateGridView {
        if let gridView { return gridView }
        let grid = CandidateGridView()
        grid.onSelect = { [weak self] index in
            guard let self else { return }
            self.feedback()
            self.closeGrid()
            self.controller.selectCandidate(at: index)
        }
        addSubview(grid)
        gridView = grid
        return grid
    }

    private func presentTextPanel() -> AiTextPanel {
        if let textPanel { return textPanel }
        let panel = AiTextPanel()
        panel.onAdopt = { [weak controller] index in controller?.aiAdoptTapped(index) }
        panel.onClose = { [weak controller] in controller?.aiDismissExpanded() }
        addSubview(panel)
        textPanel = panel
        setNeedsLayout()
        return panel
    }

    private func openGrid() {
        guard !candidates.isEmpty else { return }
        gridOpen = true
        let grid = presentGrid()
        grid.candidates = candidates
        grid.isHidden = false
        controller.expandCandidates()
        setNeedsLayout()
        let chevron = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        expandButton.setImage(UIImage(systemName: "chevron.up", withConfiguration: chevron), for: .normal)
        expandButton.accessibilityLabel = "收起候选"
        setNeedsLayout()
    }

    private func closeGrid() {
        gridOpen = false
        gridView?.isHidden = true
        controller.collapseCandidates()
        let chevron = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        expandButton.setImage(UIImage(systemName: "chevron.down", withConfiguration: chevron), for: .normal)
        expandButton.accessibilityLabel = "展开候选"
    }

    private func reloadLayoutIfNeeded() {
        let layout = currentLayout()
        if let old = renderedLayout, old.panel == layout.panel, old.mode == layout.mode, old.showGlobe == layout.showGlobe,
           old.numberRow == layout.numberRow {
            if old.shift == layout.shift, old.returnKind == layout.returnKind { return }
            // Same keys in the same places, only some titles differ (capitals, caps lock, the
            // return key): retitle the existing buttons instead of replacing them.
            let specs = layout.rows.flatMap { $0 }.compactMap { item -> KeySpec? in
                if case .key(let spec) = item { return spec }
                return nil
            }
            if specs.count == keyButtons.count {
                renderedLayout = layout
                rows = layout.rows
                for (button, spec) in zip(keyButtons, specs) { button.update(spec) }
                return
            }
        }
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
        // The grid and the text panel stay above the keys.
        if let gridView { bringSubviewToFront(gridView) }
        if let textPanel { bringSubviewToFront(textPanel) }
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
            button.onTap = { [weak self] key in self?.controller.handle(key.spec.action, timestamp: key.lastTouchTimestamp) }
        }
    }

    // MARK: feedback

    /// Haptics and the key click need Full Access in a keyboard extension (`hapticsEnabled`). The generator is
    /// prepared again after every tap so the next one has no latency.
    private func feedback() {
        guard hapticsEnabled else { return }
        impact.impactOccurred()
        impact.prepare()
        UIDevice.current.playInputClick()
    }

    private func touchDown(_ key: KeyButton) {
        feedback()
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
        scheduleDeleteTimer(after: 0.45)
    }

    private func repeatDelete() {
        controller.handle(.delete)
        scheduleDeleteTimer(after: 0.08)
    }

    /// In the common run loop modes: a timer in the default mode stops while UIKit tracks a touch.
    private func scheduleDeleteTimer(after interval: TimeInterval) {
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in self?.repeatDelete() }
        RunLoop.main.add(timer, forMode: .common)
        deleteTimer = timer
    }

    /// Stops a held delete (the keyboard goes away or turns while a finger is down: no touch-up will come).
    public func stopDeleteRepeat() {
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
        CGSize(width: UIView.noIntrinsicMetric, height: Self.preferredHeight(landscape: isLandscape, numberRow: numberRowEnabled))
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let m = Self.metrics(landscape: isLandscape)
        let width = bounds.width
        // In landscape the notch and the home indicator reserve the sides: nothing is laid out under them.
        let left = safeAreaInsets.left
        let right = safeAreaInsets.right
        let usable = max(width - left - right, 0)
        compositionLabel.frame = CGRect(x: left + 12, y: m.top, width: max(usable - 24, 0), height: m.composition)
        let candidateTop = m.top + m.composition
        let expand = expandButton.isHidden ? 0 : m.expandWidth
        candidateView.frame = CGRect(x: left, y: candidateTop, width: max(usable - expand, 0), height: m.candidates)
        expandButton.frame = CGRect(x: width - right - m.expandWidth, y: candidateTop, width: m.expandWidth, height: m.candidates)
        let aiTop = candidateTop + m.candidates
        aiBar.frame = CGRect(x: left, y: aiTop, width: usable, height: m.aiBar)
        separator.frame = CGRect(x: 0, y: aiTop, width: width, height: 1 / max(traitCollection.displayScale, 1))

        // Key rows share the height under the AI bar equally: a panel with four rows has taller keys than
        // the letters panel with its number row, and the keyboard keeps one height.
        let keysTop = m.keysTop
        let rowCount = max(rows.count, 1)
        let available = max(bounds.height - keysTop - m.bottom, 0)
        let keyHeight = max((available - CGFloat(rowCount - 1) * m.rowGap) / CGFloat(rowCount), 0)
        var y = keysTop
        var buttonIndex = 0
        for row in rows {
            let totalWeight = row.reduce(0) { $0 + $1.weight }
            let gaps = CGFloat(max(row.count - 1, 0)) * m.keyGap
            let unit = (usable - 2 * m.side - gaps) / totalWeight
            var x = left + m.side
            for item in row {
                let itemWidth = unit * item.weight
                if case .key = item {
                    keyButtons[buttonIndex].frame = CGRect(x: x, y: y, width: itemWidth, height: keyHeight).integral
                    buttonIndex += 1
                }
                x += itemWidth + m.keyGap
            }
            y += keyHeight + m.rowGap
        }

        // The candidate grid and the AI text panel cover everything under the candidate row.
        let coverTop = aiTop
        let cover = CGRect(x: left, y: coverTop, width: usable, height: max(bounds.height - coverTop, 0))
        gridView?.frame = cover
        textPanel?.frame = cover
    }

    public override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.verticalSizeClass != traitCollection.verticalSizeClass {
            invalidateIntrinsicContentSize()
            stopDeleteRepeat()
        }
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
        feedback()
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
        // The reading of a phrase repeats what the composition row shows; only a single character
        // keeps it (你 nǐ), which is what tells homophones apart.
        if !candidate.comment.isEmpty, candidate.text.count == 1 {
            result.append(NSAttributedString(string: " " + candidate.comment, attributes: [
                .font: KeyboardTheme.commentFont, .foregroundColor: KeyboardTheme.secondaryText,
            ]))
        }
        return result
    }

    static func width(for candidate: RimeCandidate) -> CGFloat {
        ceil(attributed(candidate).size().width) + 22
    }

    func configure(_ candidate: RimeCandidate, highlighted: Bool, index: Int, identifierPrefix: String = "oc.candidate.") {
        label.attributedText = Self.attributed(candidate)
        contentView.backgroundColor = highlighted ? KeyboardTheme.candidateHighlight : .clear
        accessibilityIdentifier = identifierPrefix + String(index)
        accessibilityLabel = candidate.text
        accessibilityTraits = highlighted ? [.button, .selected] : .button
    }
}

/// `UIDevice.playInputClick()` plays the system key click only when a superview of the touched view says clicks
/// are wanted (and the person has keyboard clicks switched on in Settings).
extension KeyboardView: UIInputViewAudioFeedback {
    public var enableInputClicksWhenVisible: Bool { true }
}
