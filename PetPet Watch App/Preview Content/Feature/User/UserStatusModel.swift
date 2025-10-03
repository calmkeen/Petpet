//
//  UserStatusModel.swift
//  PetPet Watch App
//
//  Created by calmkeen on 10/3/25.
//

import Foundation

struct UserStatusModel: Codable {
    var userId: String
    var createdDate: Date
    var isDeleted: Bool = false
    var deletedDate: Date
    var LastModifiedDate: Date
    
}
