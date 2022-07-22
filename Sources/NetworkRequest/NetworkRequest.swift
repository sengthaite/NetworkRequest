//
//  NetworkRequest.swift
//  Z1
//
//  Created by Sengthai Te on 21/4/22.
//  Copyright © 2022 Gaeasys. All rights reserved.
//

import Foundation
import Network
import Combine

public typealias DataTaskIdentity = String

public let Http = NetworkRequest.instance

open class NetworkRequest: NSObject, URLSessionDelegate {
    
    static public let instance = NetworkRequest()
    
    public let networkMonitorQueueName = "NetworkRequestMonitor"
    
    public var isConnected: Bool?
    
    public var enableNetworkMonitor: Bool = true {
        didSet {
            guard enableNetworkMonitor else {
                isConnected = nil
                networkMonitor?.cancel()
                return
            }
            if let _ = networkMonitor { return }
            let queue = DispatchQueue(label: networkMonitorQueueName)
            networkMonitor = NWPathMonitor()
            networkMonitor.pathUpdateHandler = { [weak self] path in
                switch path.status {
                case .satisfied:
                    self?.isConnected = true
                    print("Network connected")
                    NotificationCenter.default.post(name: .networkRequestMonitor, object: true)
                    guard let successReloadableObject = self?.successReloadableObject else {
                        return
                    }
                    for reloadableObject in successReloadableObject {
                        if reloadableObject.value?.1 ?? false {
                            reloadableObject.value?.0.reloadData()
                        }
                    }
                case .requiresConnection, .unsatisfied:
                    self?.isConnected = false
                    print("Network disconnected")
                    NotificationCenter.default.post(name: .networkRequestMonitor, object: false)
                @unknown default:
                    break
                }
            }
            networkMonitor.start(queue: queue)
        }
    }
    
    public var networkMonitor: NWPathMonitor!
    
    public var successReloadableObject = [String: (DataReloadable, Bool)?]()
    
    private var dataTaskRequests = [DataTaskIdentity: URLSessionDataTask]()
    
    public func getDataTask(by key: DataTaskIdentity)->URLSessionDataTask? {
        dataTaskRequests[key]
    }
    
    public func cancelAllDataTasks() {
        dataTaskRequests.forEach { key, dataTask in
            dataTask.cancel()
        }
        dataTaskRequests.removeAll()
    }
    
    public func cancelDataTask(with key: DataTaskIdentity) {
        dataTaskRequests[key]?.cancel()
        dataTaskRequests.removeValue(forKey: key)
    }
    
    public func addReloadableObject(_ reloadableClass: NSObject, reloadWhenReconnected: Bool = false) {
        guard
            let name = reloadableClass.stringFromClass,
            let reloadableClass = reloadableClass as? DataReloadable
        else {
            print("Add reloadable object failed")
            return
        }
        successReloadableObject[name] = (reloadableClass, reloadWhenReconnected)
    }
    
    public func cancelAllReloadableObjects() {
        successReloadableObject.removeAll()
    }
    
    public func cancelReloadableObject(_ reloadableClass: NSObject) {
        guard
            let _ = reloadableClass as? DataReloadable,
            let name = reloadableClass.stringFromClass
        else {
            print("Cancel reloadable object failed")
            return
        }
        successReloadableObject.removeValue(forKey: name)
    }
    
    private func checkReloadData(shouldReloadData: Bool) {
        if shouldReloadData {
            for reloadableObject in successReloadableObject {
                reloadableObject.value?.0.reloadData()
            }
        }
    }
    
    public func request(key: DataTaskIdentity? = nil,
                        urlRequest: URLRequest,
                        operationQueue: OperationQueue? = nil,
                        config: URLSessionConfiguration? = nil,
                        enableLoadingClosure: Bool = true,
                        shouldReloadData: Bool = false,
                        showLogResponse: Bool = false,
                        completion: ((Result<Codable, Error>)->Void)?
    ) {
        if let isConnected = isConnected, !isConnected {
            completion?(.failure(URLResponseGroup.unknown))
            return
        }
        let session: URLSession
        if let config = config {
            session = URLSession(configuration: config, delegate: self, delegateQueue: operationQueue)
        } else {
            session = URLSession.shared
        }
        if enableLoadingClosure {
            NotificationCenter.default.post(name: .networkRequesting, object: true)
        }
        let dataTaskKey = key ?? UUID().uuidString
        let dataTask = session.dataTask(with: urlRequest) { [weak self] data, response, error in
            self?.cancelDataTask(with: dataTaskKey)
            DispatchQueue.main.async {
                if enableLoadingClosure {
                    NotificationCenter.default.post(name: .networkRequesting, object: false)
                }
                guard let response = response as? HTTPURLResponse else {
                    print("response is not HTTPURLResponse")
                    return
                }
                let statusCode = response.statusCode
                switch URLResponseGroup(rawValue: statusCode) {
                case .informationalResponse:
                    print("Client should do extra work and no response available yet.")
                    completion?(.failure(URLResponseGroup.informationalResponse))
                case .successfulResponse:
                    self?.checkReloadData(shouldReloadData: shouldReloadData)
                    completion?(.success(data))
                case .redirectionMessages:
                    print("Redirection message with response: ", response as Any)
                    completion?(.failure(URLResponseGroup.redirectionMessages))
                case .clientErrorResponses:
                    print("Client error: ", error as Any)
                    completion?(.failure(URLResponseGroup.clientErrorResponses))
                case .serverErrorResponses:
                    print("Server errror: ", error as Any)
                    completion?(.failure(URLResponseGroup.serverErrorResponses))
                default:
                    print("Undefined status code")
                    completion?(.failure(URLResponseGroup.unknown))
                }
                if showLogResponse {
                    print("\n\n============================================================\n\n")
                    if let data = data {
                        print("######### DATA #########")
                        print(data.prettyPrintedString)
                        print("########################")
                    }
                    print("######### RESPONSE #########")
                    print(response)
                    print("############################")
                    if let error = error {
                        print("######### ERROR #########")
                        print(error.localizedDescription)
                        print("#########################")
                    }
                    print("\n\n============================================================\n\n")
                }
            }
        }
        dataTaskRequests[dataTaskKey] = dataTask
        dataTask.resume()
    }
    
    public func request<T>(
        key: DataTaskIdentity? = nil,
        requestResource: ResourceRequestable,
        responseType: T.Type,
        showLogResponse: Bool = false,
        operationQueue: OperationQueue? = nil,
        config: URLSessionConfiguration? = nil,
        enableLoadingClosure: Bool = true,
        shouldReloadData: Bool = false,
        completion: ((_ data: T?, _ error: Error?)->Void)?
    ) where T: Codable {
        request(key: key, urlRequest: requestResource.urlRequest, operationQueue: operationQueue, config: config, enableLoadingClosure: enableLoadingClosure, shouldReloadData: shouldReloadData, showLogResponse: showLogResponse) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    guard let data = (data as? Data)?.decode(to: responseType.self) else {
                        print("Decoding failed: ", requestResource.path as Any, " as: ", responseType)
                        return
                    }
                    completion?(data, URLResponseGroup.unknown)
                case .failure(let error):
                    completion?(nil, error)
                }
            }
        }
    }
    
}

extension NetworkRequest {
    
    // Request with codable response
    public func requestOnData<T>(
        key: DataTaskIdentity? = nil,
        requestResource: ResourceRequestable,
        responseType: T.Type,
        operationQueue: OperationQueue? = nil,
        config: URLSessionConfiguration? = nil,
        codableData: @escaping (T)->Void,
        enableLoadingClosure: Bool = true,
        shouldReloadData: Bool = false
    ) where T: Codable {
        request(key: key, urlRequest: requestResource.urlRequest, operationQueue: operationQueue, config: config, enableLoadingClosure: enableLoadingClosure, shouldReloadData: shouldReloadData) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    guard let data = (data as? Data)?.decode(to: responseType.self) else {
                        return
                    }
                    codableData(data)
                case .failure:
                    break
                }
            }
        }
    }
    
    // Request result with Promise like and codable response
    @discardableResult
    public func requestWithHandler<T: Codable>(
        key: DataTaskIdentity? = nil,
        requestResource: ResourceRequestable,
        responseType: T.Type,
        operationQueue: OperationQueue? = nil,
        config: URLSessionConfiguration? = nil,
        enableLoadingClosure: Bool = true,
        shouldReloadData: Bool = false
    ) -> NetworkRequestHandler<T> {
        NetworkRequestHandler(
            key: key,
            requestResource: requestResource,
            responseType: T.self,
            operationQueue: operationQueue,
            config: config,
            enableLoadingClosure: enableLoadingClosure,
            shouldReloadData: shouldReloadData
        )
    }
    
    @discardableResult
    public func requestWithHandler<T: Codable>(
        key: DataTaskIdentity? = nil,
        urlRequest: URLRequest,
        responseType: T.Type,
        shouldReloadData: Bool = false,
        enableLoadingClosure: Bool = true,
        operationQueue: OperationQueue? = nil,
        config: URLSessionConfiguration? = nil
    ) -> NetworkRequestHandler<T> {
        NetworkRequestHandler(
            key: key,
            urlRequest: urlRequest,
            shouldReloadData: shouldReloadData,
            enableLoadingClosure: enableLoadingClosure,
            operationQueue: operationQueue,
            config: config
        )
    }
    
    @discardableResult
    public func requestWithHandler(
        urlRequests: [(key: DataTaskIdentity? , requestResource: ResourceRequestable)],
        shouldReloadData: Bool = false,
        enableLoadingClosure: Bool = true,
        strict: Bool = true
    )-> BatchNetworkRequestHandler {
        if enableLoadingClosure {
            NotificationCenter.default.post(name: .networkRequesting, object: true)
        }
        return BatchNetworkRequestHandler(
            urlRequests: urlRequests,
            strict: strict) { [weak self] in
                if enableLoadingClosure {
                    NotificationCenter.default.post(name: .networkRequesting, object: false)
                }
                self?.checkReloadData(shouldReloadData: shouldReloadData)
            }
    }
    
}

public enum URLResponseGroup: String, RawRepresentable, Error {
    
    public typealias RawValue = String
    
    case informationalResponse
    case successfulResponse
    case redirectionMessages
    case clientErrorResponses
    case serverErrorResponses
    case unknown
    
    init?(rawValue: Int) {
        switch rawValue {
        case 100...199:
            self = .informationalResponse
        case 200...299:
            self = .successfulResponse
        case 300...399:
            self = .redirectionMessages
        case 400...499:
            self = .clientErrorResponses
        case 500...599:
            self = .serverErrorResponses
        default:
            self = .unknown
        }
    }
    
}

public extension Data {
    
    var prettyPrintedString: String {
        if let jsonObj = try? JSONSerialization.jsonObject(with: self),
           let dataJson = try? JSONSerialization.data(withJSONObject: jsonObj, options: [.prettyPrinted, .fragmentsAllowed, .sortedKeys]),
           let dataJsonString = String(data: dataJson, encoding: .utf8)
        {
            return dataJsonString
        } else {
            return String(data: self, encoding: .utf8) ?? ""
        }
    }
    
    func decode<T: Codable>(to type: T.Type)->T? {
        do {
            return try JSONDecoder().decode(type.self, from: self)
        } catch {
            print("Decoding failed \(error.localizedDescription): ", type.self)
            return nil
        }
    }
    
}

public extension Notification.Name {
    static let networkRequestMonitor = Notification.Name(rawValue: "networkRequestMonitor")
    static let networkRequesting = Notification.Name(rawValue: "networkRequesting")
}

public extension Encodable {
    
    var toData: Data? {
        try? JSONEncoder().encode(self)
    }
    
}

public extension String {
    
    var stringToClass: AnyClass? {
        NSClassFromString(self)
    }
    
}

public extension NSObject {
    
    var stringFromClass: String? {
        NSStringFromClass(type(of: self))
    }
    
}
