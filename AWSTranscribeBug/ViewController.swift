//
//  ViewController.swift
//  AWSTranscribeBug
//
//  Created by João Souza on 23/11/19.
//  Copyright © 2019 Example. All rights reserved.
//

import UIKit
import AWSCore
import AWSS3
import AWSTranscribe

class ViewController: UIViewController {
    
    let accessKey = "YOUR KEY HERE"
    let secretKey = "YOUR KEY HERE"
    let s3Bucket = "YOUR S3 BUCKET"
    let s3Key = "YOUR S3 KEY"
    let region = AWSRegionType.USEast1

    override func viewDidLoad() {
        super.viewDidLoad()
        let audioURL = Bundle.main.url(forResource: "sample", withExtension: "wav")
        transcribeAudio(audioURL!)
    }
    
    func transcribeAudio(_ audioURL: URL) {
        DispatchQueue.global().async {
            
            let credentialsProvider = AWSStaticCredentialsProvider(accessKey: self.accessKey, secretKey: self.secretKey)
            let configuration = AWSServiceConfiguration(region: self.region, credentialsProvider: credentialsProvider)
            AWSServiceManager.default().defaultServiceConfiguration = configuration
            
            self.uploadFileToS3(audioURL).continueWith { task -> Any? in
                guard
                    task.error == nil,
                    let result = task.result else {
                        print("ERROR ON uploadFileToS3")
                        return nil
                }
                let mediaFileURI = "s3://\(result.bucket)/\(result.key)"
                return self.startTranscriptionJob(mediaFileURI)
            }.continueWith { task -> Any? in
                guard
                    task.error == nil,
                    let transcriptionJobName = task.result?.transcriptionJob?.transcriptionJobName
                    else {
                        print("ERROR ON startTranscriptionJob")
                        return nil
                }
                return self.getTranscriptionJob(transcriptionJobName)
            }.continueWith { task -> Any? in
                guard
                    task.error == nil,
                    let transcriptFileUri = task.result?.transcriptionJob??.transcript?.transcriptFileUri
                    else {
                        print("ERROR ON getTranscriptionJob")
                        return nil
                }
                print(transcriptFileUri)
                return nil
            }
        }
    }
    
    fileprivate func uploadFileToS3(
        _ fileURL: URL
    ) -> AWSTask<AWSS3TransferUtilityMultiPartUploadTask> {
        
        let bucket = s3Bucket
        let key = s3Key
        let contentType = "audio/x-wav"
        let transferUtility = AWSS3TransferUtility.default()
        return transferUtility.uploadUsingMultiPart(
            fileURL: fileURL,
            bucket: bucket,
            key: key,
            contentType: contentType,
            expression: nil)
    }
    
    fileprivate func startTranscriptionJob(
        _ mediaFileURI: String
    ) -> AWSTask<AWSTranscribeStartTranscriptionJobResponse>? {
        
        let media = AWSTranscribeMedia()
        media?.setValue(mediaFileURI, forKey: "MediaFileUri")
        
        guard let request = AWSTranscribeStartTranscriptionJobRequest() else { return nil }
        request.languageCode = .enUS
        request.media = media
        request.mediaFormat = .wav
        request.transcriptionJobName = "aws-transcribe-bug-\(UUID().uuidString)"
        
        let transcribe = AWSTranscribe.default()
        return transcribe.startTranscriptionJob(request)
    }
    
    fileprivate func getTranscriptionJob(
        _ transcriptionJobName: String
    ) -> AWSTask<AWSTranscribeGetTranscriptionJobResponse>? {
        
        let transcribe = AWSTranscribe.default()
        
        guard let request = AWSTranscribeGetTranscriptionJobRequest() else { return nil }
        request.transcriptionJobName = transcriptionJobName
        
        /// `getTranscriptionJob` repeatedly until the status is no longer `inProgress`.
        /// However, `getTranscriptionJob` never completes.
        var transcriptionInProgress = true
        while transcriptionInProgress {
            print("getTranscriptionJob")
            transcribe.getTranscriptionJob(request).continueWith { task -> Any? in
                print("getTranscriptionJob never completes...")
                let transcriptionJob = task.result?.transcriptionJob
                transcriptionInProgress = transcriptionJob?.transcriptionJobStatus == .inProgress
                return nil
            }.waitUntilFinished()
        }
        print("...after the getTranscriptionJob")
          
        /// `listTranscriptionJobs` also never completes, no matter if you `waitUntilFinished` or not.
        /// Try by commenting-out the `while` block above and uncommenting the lines below.
        
//        let listRequest = AWSTranscribeListTranscriptionJobsRequest()
//        transcribe.listTranscriptionJobs(listRequest!).continueWith { task -> Any? in
//            print("listTranscriptionJobs never completes...")
//            return nil
//        }
//
//        let listRequest2 = AWSTranscribeListTranscriptionJobsRequest()
//        transcribe.listTranscriptionJobs(listRequest2!).continueWith { task -> Any? in
//            print("listTranscriptionJobs.waitUntilFinished never completes...")
//            print(task)
//            return nil
//        }.waitUntilFinished()
        
        return transcribe.getTranscriptionJob(request)
    }
    
}

