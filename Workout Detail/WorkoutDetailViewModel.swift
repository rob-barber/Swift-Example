//
// Created by Robert Barber on 11/9/19.
// Copyright (c) 2019 Rob Barber. All rights reserved.
//

import Foundation
import RealmSwift
import RxSwift
import RxCocoa
import RxRealm
import RxDataSources
import Sentry
import SwiftyJSON

/// List of sections that contain WorkoutItems
struct WorkoutsDetailSectionData {
    var header: String

    /// Should be a list of unmanaged Realm objects
    var items:[Item]
}

extension WorkoutsDetailSectionData: AnimatableSectionModelType {
    typealias Item = WorkoutDetailItemData

    public var identity: String { self.header }

    public init(original: WorkoutsDetailSectionData, items: [Item]) {
        self = original
        self.items = items
    }
}

class WorkoutDetailViewModel: ViewModel, ExercisePlanManaging {

    let outputData = BehaviorRelay<[WorkoutsDetailSectionData]>(value: [])

    // region MARK: Text
    let deleteAlertTitle = "WARNING"
    let deleteAlertMessage = """
                             Are you sure you want to remove this item from the workout?
                             """
    // endregion

    /// Unmanaged to avoid issues with Realm.
    var unmanagedWorkout: Workout
    let database: Database
    let api: RestfulApi
    let disposeBag = DisposeBag()

    init(unmanagedWorkout:Workout, database:Database, api:RestfulApi) {
        self.unmanagedWorkout = unmanagedWorkout
        self.database = database
        self.api = api
    }

    func configure() {
        let query = self.database.objects(ExercisePlan.self).filter("workoutId == %@", self.unmanagedWorkout.id)
        Observable.collection(from: query)
            .subscribe(onNext: { [weak self] updatedExercisePlans in

                guard let strongSelf = self else { return }

                // Sort and convert into unmanaged objects.
                let sortedItems = updatedExercisePlans.sorted(byKeyPath: "order", ascending: true).toArray().map { 
                    exercisePlan -> WorkoutDetailItemData in

                    return WorkoutDetailItemData(managedExercisePlan: exercisePlan)
                }
                let sectionData = WorkoutsDetailSectionData(header: "1", items: sortedItems)
                strongSelf.outputData.accept([sectionData])

            }).disposed(by: self.disposeBag)
    }

}

// MARK:- Data Handling
extension WorkoutDetailViewModel {
    
    func onExerciseSelected(exercises: [Exercise]) {
        guard exercises.count > 0 else {
            return
        }

        let sortedExercises = exercises.sorted { $0.name < $1.name }
        var order = self.maxOrderExercisePlans(forWorkout: self.unmanagedWorkout) + 1

        // Commit the selection to the local database and update values
        let exercisePlans:[ExercisePlan] = sortedExercises.map { (exercise:Exercise) -> ExercisePlan in
            let exercisePlan = ExercisePlan()
            exercisePlan.exerciseId = exercise.id
            exercisePlan.workoutId = self.unmanagedWorkout.id

            return exercisePlan
        }

        // Wrap changes in one write block so it is all committed at the same time
        self.database.write {
            exercisePlans.forEach { item in
                item.order = order
                item.synced = false

                order = order + 1

                // Save the ExercisePlan to it's parent objects
                guard let workout = self.database.object(Workout.self, forPrimaryKey: item.workoutId),
                      let exercise = self.database.object(Exercise.self, forPrimaryKey: item.exerciseId) else {
                    print(self.tag + "Could not save new exercise plan to parent objects.")
                    return
                }

                workout.exercisePlans.append(item)
                exercise.exercisePlans.append(item)
            }
        }

        // Only send the network request to the server after the local database has been updated
        let query = self.database.objects(ExercisePlan.self)
        Observable.collection(from: query)
                .take(1)
                .subscribe(onNext: { [weak self] _ in

                    guard let strongSelf = self else { return }

                    // Persist the updated objects to the server. NOTE: This can just happen in the background.
                    let requestSingle: Single<JSON> = strongSelf.api.updateObjects(exercisePlans, url: APIConstants.Restful.exercisePlans)
                    requestSingle.subscribe { [weak self] event in

                        guard let strongSelf = self else {
                            return
                        }

                        switch event {
                        case .success(let jsonResponse):
                            guard let jsonArray = jsonResponse.array else {
                                print(strongSelf.tag + "Could not parse array from JSON object")
                                return
                            }

                            let unmanagedPlans = jsonArray.compactMap { json -> ExercisePlan? in
                                guard let exercisePlan = ExercisePlan(json: json) else {
                                    return nil
                                }

                                exercisePlan.synced = true
                                return exercisePlan
                            }

                            strongSelf.database.addOrUpdate(unmanagedPlans)

                        case .error(let error):
                            print(strongSelf.tag + "Could not update ExercisePlans after exercise was selected: \(error)")
                            SentryService.logError(error: error, level: .info)
                        }

                    }.disposed(by: strongSelf.disposeBag)
        }).disposed(by: self.disposeBag)

    }

    func deleteExercisePlan(atIndex indexPath:IndexPath) -> Completable {
        return Completable.create { [weak self] observer in

            guard let strongSelf = self else {
                observer(.error(ConfigurationError.noSelfObject))
                return Disposables.create()
            }

            let exercisePlan = strongSelf.outputData.value[indexPath.section].items[indexPath.row].exercisePlan

            strongSelf.api.deleteObject(withId: exercisePlan.id, baseUrl: APIConstants.Restful.exercisePlans)
                    .subscribe { [weak self] event in

                        guard let strongSelf = self else {
                            observer(.error(ConfigurationError.noSelfObject))
                            return
                        }

                        switch event {
                        case .success(_):
                            strongSelf.database.delete(ExercisePlan.self, forId: exercisePlan.id)
                            observer(.completed)

                        case .error(let error):
                            observer(.error(error))
                        }

                    }.disposed(by: strongSelf.disposeBag)

            return Disposables.create()
        }
    }
    
}
