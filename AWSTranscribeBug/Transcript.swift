//
//  Transcript.swift
//  AWSTranscribeBug
//
//  Created by João Souza on 14/12/19.
//  Copyright © 2019 Example. All rights reserved.
//

import Foundation

struct Transcription: Codable {
    var jobName: String
    var accountId: String
    var status: String
    var results: Results
    
    struct Results: Codable {
        var transcripts: [Transcript]
        var items: [Item]
        
        struct Transcript: Codable {
            var transcript: String
        }
        
        struct Item: Codable {
            var startTime: String?
            var endTime: String?
            var type: String
            var alternatives: [Alternative]
            
            var actualStartTime: Double? {
                get { startTime == nil ? nil : Double(startTime!) }
                set { startTime = newValue == nil ? nil : String(newValue!) }
            }
            
            var actualEndTime: Double? {
                get { endTime == nil ? nil : Double(endTime!) }
                set { endTime = newValue == nil ? nil : String(newValue!) }
            }
            
            struct Alternative: Codable {
                var confidence: String
                var content: String
            }
        }
    }
}
