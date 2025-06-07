//
//  ModalID.swift
//  NavigationFrame3
//
//  Created by Erick Manrique on 6/4/25.
//
import Foundation

struct ModalID: Identifiable, Equatable {
    let id: UUID
    init(_ id: UUID) { self.id = id }
}
