//
//  ResourceRequestable.swift
//  Z1
//
//  Created by Sengthai Te on 21/4/22.
//  Copyright © 2022 Gaeasys. All rights reserved.
//

import Foundation

public protocol ResourceRequestable {
    
    var baseURL: URL { get }
    
    var prefix: String? { get }
    
    var path: String? { get }
    
    var method: HttpMethod { get }
    
    var body: Data? { get }
    
    var version: String? { get }
    
    var params: [String: String]? { get }
    
    var authorizeType: AuthorizationType { get }
    
    var  header: [String: String]? { get }

    var timeoutInterval: TimeInterval { get }
}

public extension ResourceRequestable {
    
    var urlRequest: URLRequest {
        let resource = self
        var url = resource.baseURL
        if let prefix = resource.prefix {
            url.appendPathComponent(prefix)
        }
        if let version = resource.version {
            url.appendPathComponent(version)
        }
        if let path = resource.path {
            url.appendPathComponent(path)
        }
        
        if let params = resource.params,
            var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true) {
            
            var queryItems = [URLQueryItem]()
            for (key, value) in params {
                queryItems.append(URLQueryItem(name: key, value: value))
            }
            
            urlComponents.queryItems = queryItems
            if let fullURL = urlComponents.url {
                url = fullURL
            }
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = resource.method.rawValue
        request.httpBody = resource.body
        if let headers = resource.header {
            for (key, value) in headers {
                request.addValue(value, forHTTPHeaderField: key)
            }
        }
        switch resource.authorizeType {
        case .none:
            return request
        case .basic(let value),
                .apiKey(let value),
                .awsSignature(let value),
                .hawkAuth(let value),
                .digestAuth(let value),
                .oauth2(let value):
            request.addValue(value, forHTTPHeaderField: resource.authorizeType.value)
            return request
        }
    }
    
}

public enum HttpMethod: String {
    case GET
    case POST
    case PUT
    case DELETE
    case OPTIONS
    case HEAD
    case PATCH
}

public enum AuthorizationType {
    case none
    case basic(token: String)
    case apiKey(key: String)
    case digestAuth(info: String)
    case oauth2(token: String)
    case hawkAuth(info: String)
    case awsSignature(credential: String)
    
    var value: String {
        switch self {
        case .none: return ""
        case .basic: return "Authorization: Basic "
        case .apiKey: return "X-API-Key: "
        case .digestAuth: return "Authorization: Digest "
        case .oauth2: return "Authorization: Bearer "
        case .hawkAuth: return "Authorization: Hawk "
        case .awsSignature: return "Authorization: AWS4-HMAC-SHA256 "
        }
    }
}
