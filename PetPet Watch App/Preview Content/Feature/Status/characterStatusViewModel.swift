//
//  characterStatusViewModel.swift
//  PetPet Watch App
//
//  Created by calmkeen on 10/7/25.
//

import Foundation
import CoreMotion

// 스테이터스 기본은 달리기, 정지, 터치, 기본.
// 사용자가 달리면 달리는 아이콘
// 정지상태 5초 이상 유지시 기본 자세
// 정지상태에서 30초마다 고개 갸웃 
// 정지상태에서 터치시 머리를 뒷발로 긁는 모션

 enum CharacterStatus {
    case running
    case stopped
    case touching
    case defaultStatus
}

class CharacterStatusViewModel { 
    @Published var currentStatus: CharacterStatus = .defaultStatus
    @Published var isMoveStatus: Bool = false
    
    private var stopTimer: Timer?
    private var idleTimer: Timer?
    
    private let motionManager = CMMotionManager()
    
    //움직임 감지
    func startMotionDetection() {
        guard motionManager.isAccelerometerAvailable else { return }
        
        motionManager.accelerometerUpdateInterval = 0.5
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] data, error in
            guard let deviceMotion = data else { return }
            
            let acceleration = deviceMotion.userAcceleration
            
            // 가속도 벡터의 크기 계산
            let magnitude = sqrt(pow(acceleration.x, 2) + pow(acceleration.y, 2) + pow(acceleration.z, 2))
            
            // 움직임 임계값 설정 (실험적으로 조정 필요)
            let movementThreshold: Double = 1.2
            
            DispatchQueue.main.async {
                self?.updateMovementStatus(isMoving: magnitude > movementThreshold)
            }
        }
    }
    
    private func updateMovementStatus(isMoving: Bool) {
        if isMoving != isMoveStatus {
            isMoveStatus = isMoving
            
            if isMoving {
                currentStatus = .running
                resetTimers()
            } else {
                startStopTimer()
            }
        }
    }
    
    private func startStopTimer() {
        stopTimer?.invalidate()
        stopTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.currentStatus = .defaultStatus
            self?.startIdleTimer()
        }
    }
    
    private func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            // 고개 갸웃 애니메이션
            self?.currentStatus = .stopped
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self?.currentStatus = .defaultStatus
            }
        }
    }
    
    func handleTouch() {
        currentStatus = .touching
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.currentStatus = .defaultStatus
        }
    }
    
    private func resetTimers() {
        stopTimer?.invalidate()
        idleTimer?.invalidate()
    }
    
    func stopMotionDetection() {
        motionManager.stopDeviceMotionUpdates()
        resetTimers()
    }
}
