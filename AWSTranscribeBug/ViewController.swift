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
import AVFoundation

class ViewController: UIViewController {
    
    let accessKey = "YOUR KEY HERE"
    let secretKey = "YOUR KEY HERE"
    let s3Bucket = "YOUR S3 BUCKET"
    let s3Key = "YOUR S3 KEY"
    let region = AWSRegionType.USEast1

    override func viewDidLoad() {
        super.viewDidLoad()
        extractAudio { audioURL, success in
            if let audioURL = audioURL, success {
                self.transcribeAudio(audioURL)
            } else {
                print("can't extract audio")
            }
        }
        
    }
    
    fileprivate func extractAudio(completionHandler: @escaping (_ audioURL: URL?, _ success: Bool) -> Void) {
        
        // Extract audio tracks
        guard let videoUrl = Bundle.main.url(forResource: "sample", withExtension: "mov") else { return }
        let videoAsset = AVURLAsset(url: videoUrl)
        let composition = AVMutableComposition()
        for audioTrack in videoAsset.tracks(withMediaType: .audio) {
            let compositionTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid)
            try? compositionTrack?.insertTimeRange(
                audioTrack.timeRange,
                of: audioTrack,
                at: audioTrack.timeRange.start)
        }

        // Create the output file
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        let date = dateFormatter.string(from: Date())
        guard let outputURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("legendary-\(date).mov") else
        {
            completionHandler(nil, false)
            return
        }

        // Export the audio tracks into the output file
        let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHEVCHighestQuality)
        exportSession?.outputURL = outputURL
        exportSession?.outputFileType = .mov
        exportSession?.exportAsynchronously {
            completionHandler(
                exportSession?.outputURL,
                exportSession?.status == .completed
            )
        }
        
    }
    
    func transcribeAudio(_ audioURL: URL) {
        let credentialsProvider = AWSStaticCredentialsProvider(accessKey: accessKey, secretKey: secretKey)
        let configuration = AWSServiceConfiguration(region: region, credentialsProvider: credentialsProvider)
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
        }.continueWith(executor: AWSExecutor(dispatchQueue: DispatchQueue.global())) { task -> Any? in
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
                let transcriptFileUri = task.result?.transcriptionJob??.transcript?.transcriptFileUri,
                let transcription = try? self.downloadTranscription(transcriptFileUri)
                else {
                    print("ERROR ON getTranscriptionJob")
                    return nil
            }
            print(transcription.results.transcripts.first?.transcript ?? "[no transcript]")
            return nil
        }
        
//        let transcriptionJobName = "timeline.mov"
//        self.getTranscriptionJob(transcriptionJobName)!.continueWith { task -> Any? in
//            guard
//                task.error == nil,
//                let transcriptFileUri = task.result?.transcriptionJob?.transcript?.transcriptFileUri,
//                let transcription = try? self.downloadTranscription(transcriptFileUri) else
//            {
//                print("ERROR ON getTranscriptionJob")
//                return nil
//            }
//            print(transcription.jobName)
//            return nil
//        }
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
        request.languageCode = .ptBR
        request.media = media
        request.transcriptionJobName = "aws-transcribe-ptbr-\(UUID().uuidString)"
        
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
        var transcriptionInProgress = true
        while transcriptionInProgress {
            print("getTranscriptionJob began")
            transcribe.getTranscriptionJob(request).continueWith { task -> Any? in
                print("getTranscriptionJob ended")
                let transcriptionJob = task.result?.transcriptionJob
                transcriptionInProgress = transcriptionJob?.transcriptionJobStatus == .inProgress
                return nil
            }.waitUntilFinished()
            if transcriptionInProgress { sleep(5) }
        }
        print("...after the getTranscriptionJob")
        
        return transcribe.getTranscriptionJob(request)
    }
    
    fileprivate func downloadTranscription(_ transcriptFileUri: String) throws -> Transcription {
        print("downloadTranscription began")
        let url = URL(string: transcriptFileUri)
        let data = try Data(contentsOf: url!)
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        let transcription = try jsonDecoder.decode(Transcription.self, from: data)
        print(transcription.results.transcripts.first?.transcript ?? "[no transcript]")
        return transcription
    }
    
}
