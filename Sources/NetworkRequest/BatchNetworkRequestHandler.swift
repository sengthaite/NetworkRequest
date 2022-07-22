//
//  BatchNetworkRequestHandler.swift
//  Z1
//
//  Created by Sengthai Te on 12/5/22.
//  Copyright © 2022 Gaeasys. All rights reserved.
//

import Foundation

open class BatchNetworkRequestHandler {
    
    private var successCompletion: (([DataTaskIdentity: Codable]?)->Void)?
    
    private var errorCompletion: (([DataTaskIdentity: Error]?)->Void)?
    
    private var anyCompletion: (()->Void)?
    
    private var successResult = [DataTaskIdentity: Codable]()
    
    private var failureResult = [DataTaskIdentity: Error]()
    
    private var totalRequest: Int = 0
    
    @discardableResult
    public func then(_ completion: (()->Void)? = nil)-> Self {
        anyCompletion = completion
        return self
    }
    
    @discardableResult
    public func then(_ completion: (([DataTaskIdentity : Codable]?)->Void)? = nil)-> Self {
        successCompletion = completion
        return self
    }
    
    @discardableResult
    public func `catch`(_ completion: (([DataTaskIdentity: Error]?)->Void)? = nil)-> Self {
        errorCompletion = completion
        return self
    }
    
    deinit {
        print("deinit: \(self)")
    }
    
    public init(
        urlRequests: [(key: DataTaskIdentity? , requestResource: ResourceRequestable)],
        strict: Bool = true,
        completion: (()->Void)?
    ) {
        let numRequest = urlRequests.count
        guard numRequest > 0 else {
            anyCompletion?()
            completion?()
            return
        }
        totalRequest = numRequest
        for request in urlRequests {
            let requestKey = request.key ?? UUID().uuidString
            Http.request(
                key: requestKey,
                urlRequest: request.requestResource.urlRequest,
                operationQueue: nil,
                config: nil,
                enableLoadingClosure: false,
                shouldReloadData: false) { [self] result in
                    totalRequest -= 1
                    switch result {
                    case .success(let data):
                        successResult[requestKey] = data
                        if totalRequest == 0 {
                            print("success batchrequest: ", successResult)
                            if strict {
                                failureResult.isEmpty ? successCompletion?(successResult) : errorCompletion?(failureResult)
                            } else {
                                successCompletion?(successResult)
                            }
                        }
                    case .failure(let error):
                        failureResult[requestKey] = error
                        if totalRequest == 0 {
                            print("failed batchrequest")
                            if strict {
                                errorCompletion?(failureResult)
                            } else {
                                successResult.isEmpty ? errorCompletion?(failureResult) : successCompletion?(successResult)
                            }
                        }
                    }
                    if totalRequest == 0 {
                        anyCompletion?()
                    }
                }
        }
    }
    
}
