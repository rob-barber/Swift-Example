//
// Created by Robert Barber on 11/9/19.
// Copyright (c) 2019 Rob Barber. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import RxDataSources

protocol WorkoutDetailViewControllerDelegate: class {

    /// Tells the delegate that the "choose workout" screen should be shown.
    func onAddExerciseToWorkout(selectionDelegate: ExerciseSelectionDelegate)

    /// Tells the delegate that the WorkoutItem detail screen should be shown
    func onExercisePlanSelected(exercisePlan:ExercisePlan)

}

final class WorkoutDetailViewController: ViewController<WorkoutDetailViewModel>, UIGestureRecognizerDelegate {

    lazy var dateCreatedLabel = self.makeDateCreatedLabel()
    lazy var sessionsLabel = self.makeSessionsLabel()
    lazy var exerciseLabel = self.makeExerciseLabel()
    lazy var tableView = self.makeTableView()
    
    let cellIdentifier = "workoutItemCell"
    let disposeBag = DisposeBag()

    weak var delegate: WorkoutDetailViewControllerDelegate?
}

// MARK:- Lifecycle
extension WorkoutDetailViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupViews()
        self.setupBindings()
    }
}

// MARK:- View Setup/Configuration
extension WorkoutDetailViewController {

    func setupViews() {
        self.title = self.viewModel.unmanagedWorkout.name
        self.view.backgroundColor = Colors.Main.background

        self.navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Edit", style: .plain, target: self, action: #selector(self.tappedEditModeButton(_:))),
            UIBarButtonItem(title: "+", style: .plain, target: self, action: #selector(self.tappedAddItemButton(_:)))
        ]

        // Setup constraints
        self.view.addSubview(dateCreatedLabel)
        self.view.addSubview(sessionsLabel)
        self.view.addSubview(exerciseLabel)
        self.view.addSubview(tableView)

        NSLayoutConstraint.activate([
            dateCreatedLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 15),
            dateCreatedLabel.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 15),

            sessionsLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 15),
            sessionsLabel.topAnchor.constraint(equalTo: dateCreatedLabel.bottomAnchor, constant: 5),

            exerciseLabel.bottomAnchor.constraint(equalTo: tableView.topAnchor, constant: -5),
            exerciseLabel.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),

            tableView.topAnchor.constraint(equalTo: sessionsLabel.bottomAnchor, constant: 50),
            tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    func makeDateCreatedLabel() -> UILabel {
        let label = Label(fontStyle: .body)
        label.text = "Date Created: \(self.viewModel.unmanagedWorkout.dateCreated.displayDateShort())"
        label.textColor = Colors.Text.primaryDark
        return label
    }

    func makeSessionsLabel() -> UILabel {
        let label = Label(fontStyle: .body)
        label.text = "Sessions: \(self.viewModel.unmanagedWorkout.sessions.count)"
        label.textColor = Colors.Text.primaryDark
        return label
    }

    func makeTableView() -> UITableView {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.delegate = self
        return table
    }

    func makeExerciseLabel() -> UILabel {
        let label = Label(fontStyle: .h2)
        label.textColor = Colors.Text.primaryDark
        label.text = "Exercises"
        return label
    }

}

// MARK:- RxBindings
extension WorkoutDetailViewController {
    func setupBindings() {

        // Set up data source
        let dataSource = RxTableViewSectionedAnimatedDataSource<WorkoutsDetailSectionData> (
            configureCell:  {
                [weak self] (dataSource, tableView, indexPath, itemData) -> UITableViewCell in
                
                guard let strongSelf = self else {
                    return UITableViewCell()
                }
                
                let cell = UITableViewCell(style: .subtitle, reuseIdentifier: strongSelf.cellIdentifier)
                cell.textLabel?.text = itemData.exercise?.name
                cell.detailTextLabel?.text = itemData.exercise?.displayType
                cell.accessoryType = .disclosureIndicator
                
                return cell
                
            }, canEditRowAtIndexPath: { _,_ in
                return true
            }
        )

        self.tableView.dataSource = nil
        self.viewModel.outputData.bind(to: self.tableView.rx.items(dataSource: dataSource)).disposed(by: self.disposeBag)
        
        // Set up delegate functionality
        self.tableView.rx.modelSelected(WorkoutDetailItemData.self).subscribe(onNext: {
            [weak self] (workoutItemData:WorkoutDetailItemData) in
                self?.delegate?.onExercisePlanSelected(exercisePlan: workoutItemData.exercisePlan)
        }).disposed(by: self.disposeBag)
    }

}

// MARK:- Actions
extension WorkoutDetailViewController {

    @objc func tappedAddItemButton(_ sender:UIButton) {
        self.delegate?.onAddExerciseToWorkout(selectionDelegate: self)
    }

    @objc func tappedEditModeButton(_ sender:UIButton) {

    }

    @objc func deleteWorkoutItem(atIndex indexPath:IndexPath) {
        self.viewModel.deleteExercisePlan(atIndex: indexPath)
                .observeOn(MainScheduler.instance)
                .subscribe { [weak self] event in

                    guard let strongSelf = self else { return }

                    switch event {
                    case .error(_):
                        strongSelf.showOkAlert(title: "Error", message: "Could not delete workout item")

                    default:
                        break // No action needed
                    }

                }.disposed(by: self.disposeBag)
    }

}

// MARK:- UITableViewDelegate
extension WorkoutDetailViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {

        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] action, view, closure in
            guard let strongSelf = self else { return }

            let center = strongSelf.tableView.convert(view.center, from: view)
            guard let indexPath = strongSelf.tableView.indexPathForRow(at: center) else {
                print(strongSelf.tag + "Could not get indexPath to delete WorkoutItem")
                return
            }

            let alert = UIAlertController(title: strongSelf.viewModel.deleteAlertTitle,
                    message: strongSelf.viewModel.deleteAlertMessage, preferredStyle: .alert)

            let deleteAction = UIAlertAction(title: "Delete", style: .destructive) { [weak self] action in 
                self?.deleteWorkoutItem(atIndex: indexPath)
                closure(true)
            }

            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { action in 
                closure(false)
            }

            alert.addAction(deleteAction)
            alert.addAction(cancelAction)

            strongSelf.present(alert, animated: true)
        }

        let editAction = UIContextualAction(style: .normal, title: "Edit") { action, view, closure in 
            // TODO: open edit screen
            closure(true)
        }

        return UISwipeActionsConfiguration(actions: [deleteAction, editAction])
    }
}

// MARK:- ExerciseSelectionDelegate
extension WorkoutDetailViewController: ExerciseSelectionDelegate {
    func onExercisesSelected(exercises: [Exercise]) {
        self.viewModel.onExerciseSelected(exercises: exercises)
        // TODO: scroll to the bottom of the tableView after the exercise has been added.
    }
}
