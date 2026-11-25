// SPDX-License-Identifier: GPL-3.0-or-later
import OCRime
import UIKit

/// The expanded candidate list: every candidate Rime offers, flowing over several rows, scrollable
/// downwards; a tap selects. The ⌃ key of the candidate row closes it. (Android: the ⌄ at the right of
/// the candidate bar.)
final class CandidateGridView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var candidates: [RimeCandidate] = [] {
        didSet {
            guard candidates != oldValue else { return }
            collection.reloadData()
            collection.setContentOffset(.zero, animated: false)
        }
    }
    var onSelect: ((Int) -> Void)?

    private let layout = UICollectionViewFlowLayout()
    private lazy var collection = UICollectionView(frame: .zero, collectionViewLayout: layout)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = KeyboardTheme.background
        accessibilityIdentifier = "oc.grid"
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 6
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 6, left: 4, bottom: 8, right: 4)
        collection.backgroundColor = .clear
        collection.dataSource = self
        collection.delegate = self
        collection.alwaysBounceVertical = true
        collection.register(CandidateCell.self, forCellWithReuseIdentifier: CandidateCell.reuseIdentifier)
        collection.accessibilityIdentifier = "oc.grid.list"
        addSubview(collection)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        collection.frame = bounds
        layout.invalidateLayout()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { candidates.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CandidateCell.reuseIdentifier, for: indexPath)
        if let cell = cell as? CandidateCell {
            cell.configure(candidates[indexPath.item], highlighted: indexPath.item == 0, index: indexPath.item, identifierPrefix: "oc.grid.item.")
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = min(max(CandidateCell.width(for: candidates[indexPath.item]), 48), max(bounds.width - 8, 48))
        return CGSize(width: width, height: 36)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(indexPath.item)
    }
}

/// A long AI candidate (more than 45 characters) read in full before it is adopted. Android shows a dialog;
/// here it is a panel inside the keyboard, because an extension has no dialogs.
final class AiTextPanel: UIView {
    var onAdopt: ((Int) -> Void)?
    var onClose: (() -> Void)?

    private let title = UILabel()
    private let textView = UITextView()
    private let adoptButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private var index = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = KeyboardTheme.background
        accessibilityIdentifier = "oc.ai.text"
        title.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = KeyboardTheme.secondaryText
        textView.isEditable = false
        textView.backgroundColor = KeyboardTheme.key
        textView.textColor = KeyboardTheme.text
        textView.font = UIFont.systemFont(ofSize: 17)
        textView.layer.cornerRadius = 8
        textView.accessibilityIdentifier = "oc.ai.text.body"
        adoptButton.setTitle("采用", for: .normal)
        adoptButton.accessibilityIdentifier = "oc.ai.text.adopt"
        adoptButton.addTarget(self, action: #selector(adopt), for: .touchUpInside)
        cancelButton.setTitle("取消", for: .normal)
        cancelButton.accessibilityIdentifier = "oc.ai.text.cancel"
        cancelButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        for view in [title, textView, adoptButton, cancelButton] { addSubview(view) }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(item: AiBarState.Item, index: Int) {
        self.index = index
        title.text = item.role.isEmpty ? "AI 候选" : "AI " + item.role
        textView.text = item.text
        isHidden = false
        setNeedsLayout()
    }

    @objc private func adopt() { onAdopt?(index) }
    @objc private func close() { onClose?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        title.frame = CGRect(x: 12, y: 6, width: width - 24, height: 18)
        let buttons: CGFloat = 40
        textView.frame = CGRect(x: 8, y: 28, width: width - 16, height: max(bounds.height - 28 - buttons - 8, 20))
        cancelButton.frame = CGRect(x: 8, y: bounds.height - buttons - 4, width: (width - 24) / 2, height: buttons)
        adoptButton.frame = CGRect(x: 16 + (width - 24) / 2, y: bounds.height - buttons - 4, width: (width - 24) / 2, height: buttons)
    }
}
