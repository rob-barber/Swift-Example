//
// Created by Rob Barber on 12/22/19.
// Copyright (c) 2019 Rob Barber. All rights reserved.
//

import Foundation
import RxDataSources

class WorkoutDetailItemData: IdentifiableType {
    let exercisePlan:ExercisePlan
    let exercise:Exercise?
    let workout:Workout?

    public var identity: String {
        return self.exercisePlan.id
    }

    init(managedExercisePlan:ExercisePlan) {
        // Create unmanaged references for everything so the Reactive DataSources can handle the data properly.

        self.exercisePlan = ExercisePlan(value: managedExercisePlan)

        let workoutRef = managedExercisePlan.workouts.first
        let exerciseRef = managedExercisePlan.exercises.first

        self.workout = workoutRef != nil ? Workout(value: workoutRef!) : nil
        self.exercise = exerciseRef != nil ? Exercise(value: exerciseRef!) : nil
    }


}

extension WorkoutDetailItemData: Equatable {
    public static func ==(lhs: WorkoutDetailItemData, rhs: WorkoutDetailItemData) -> Bool {
        return lhs.exercisePlan == rhs.exercisePlan
                && lhs.exercise == rhs.exercise
                && lhs.workout == rhs.workout
    }
}