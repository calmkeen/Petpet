//
//  userMotionCheck.swift
//  PetPet Watch App
//
//  Created by calmkeen on 9/27/25.
//

import Foundation
import CoreMotion

class userMotionCheckManager : ObservableObject{
    
    private let pedometer = CMPedometer()
     @Published var steps: Int = 0
    
    // Define the start and end dates for the query
    let startDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    let endDate = Date()

    func checkDaybyDay() {
        // Query the pedometer data
        pedometer.queryPedometerData(from: startDate, to: endDate) { data, error in
            if let error = error {
                print("An error occurred while querying pedometer data: \(error.localizedDescription)")
            } else if let data = data {
                print("Steps taken in the last 24 hours: \(data.numberOfSteps)")
                if let distance = data.distance {
                    print("Distance traveled in the last 24 hours: \(distance.floatValue) meters")
                }
            }
        }
    }
   

     
     func startPedometerUpdates() {
         guard CMPedometer.isStepCountingAvailable() else { return }
         
         pedometer.startUpdates(from: Date()) { [weak self] pedometerData, error in
             guard let pedometerData = pedometerData, error == nil else { return }
             
             DispatchQueue.main.async {
                 self?.steps = Int(pedometerData.numberOfSteps)
             }
         }
     }
     
     func stopPedometerUpdates() {
         pedometer.stopUpdates()
     }
}


