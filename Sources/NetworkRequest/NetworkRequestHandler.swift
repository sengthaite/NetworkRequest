//
//  NetworkRequestHandler.swift
//  Z1
//
//  Created by Sengthai Te on 7/5/22.
//  Copyright © 2022 Gaeasys. All rights reserved.
//

import Foundation

open class NetworkRequestHandler<T: Codable> {
    
    private var successCompletion: ((T?)->Void)?
    
    private var errorCompletion: ((Error)->Void)?
    
    private var anyCompletion: (()->Void)?
    
    @discardableResult
    public func finally(_ completion: (()->Void)? = nil)-> Self {
        anyCompletion = completion
        return self
    }
    
    @discardableResult
    public func success(_ completion: ((T?)->Void)? = nil)-> Self {
        successCompletion = completion
        return self
    }
    
    @discardableResult
    public func failure(_ completion: ((Error)->Void)? = nil)-> Self {
        errorCompletion = completion
        return self
    }
    
    deinit {
        print("deinit: \(self)")
    }
    
    public init(
        key: DataTaskIdentity? = nil,
        urlRequest: URLRequest,
        shouldReloadData: Bool = false,
        enableLoadingClosure: Bool = true,
        operationQueue: OperationQueue? = nil,
        config: URLSessionConfiguration? = nil
    ) {
        Http.request(
            key: key,
            urlRequest: urlRequest,
            operationQueue: operationQueue,
            config: config,
            enableLoadingClosure: enableLoadingClosure,
            shouldReloadData: shouldReloadData) { result in
                switch result {
                case .success(let responseData):
                    self.successCompletion?((responseData as? Data)?.decode(to: T.self))
                    self.anyCompletion?()
                case .failure(let error):
                    self.errorCompletion?(error)
                    self.anyCompletion?()
                }
            }
    }
    
    public init(
        key: DataTaskIdentity? = nil,
        requestResource: ResourceRequestable,
        responseType: T.Type,
        operationQueue: OperationQueue? = nil,
        config: URLSessionConfiguration? = nil,
        enableLoadingClosure: Bool = true,
        shouldReloadData: Bool = false
    ) {
        Http.request(
            key: key,
            requestResource: requestResource,
            responseType: T.self,
            operationQueue: operationQueue,
            config: config,
            enableLoadingClosure: enableLoadingClosure,
            shouldReloadData: shouldReloadData) { data, error in
                if let responseData = data {
                    self.successCompletion?(responseData)
                } else if let error = error {
                    self.errorCompletion?(error)
                }
                self.anyCompletion?()
            }
    }
    
}
