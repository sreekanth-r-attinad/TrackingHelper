//
//  TrackingHelper.swift
//  test
//
//  Created by Sreekanth R on 03/11/16.
//  Copyright © 2016 Sreekanth R. All rights reserved.
//

import Foundation
import UIKit

class ATTTrackingHelper: NSObject {
    
    // MARK: Pubclic Constants
    static let TrackingNotification = "RegisterForTrakingNotification"
    /// This will be used if the Helper class need to receive Notifications on Crashes
    static let CrashTrackingNotification = "RegisterForCrashTrakingNotification"
    
    // MARK: Enums
    enum TrackingTypes {
        case Automatic
        case Manual
    }
    
    enum StateTypes {
        case State
        case Event
    }
    
    enum StateTrackingMethod {
        case OnViewDidLoad
        case OnViewWillAppear
        case OnViewDidAppear
        case OnNothing
    }
    
    // MARK: Private properties    
    private var configParser:ATTConfigParser?
    private var configurationFilePath:String?
    private var stateChangeTrackingSelector:Selector?
    private var stateTrackingMethod:StateTrackingMethod?
    private let cacheDirectory = (NSSearchPathForDirectoriesInDomains(.cachesDirectory,
                                                                      .userDomainMask,
                                                                      true)[0] as String).appending("/")
    // MARK: Lazy variables
    lazy var fileManager: FileManager = {
        return FileManager.default
    }()
    
    // MARK: Shared object
    /// Shared Object
    class var helper: ATTTrackingHelper {
        struct Static {
            static let instance = ATTTrackingHelper()
        }
        return Static.instance
    }
    
    // MARK: Public Methods
    func startTrackingWithConfigurationFile(pathForFile:String?) -> Void {
        self.startTrackingWithConfigurationFile(pathForFile: pathForFile,
                                                stateTracking: .Manual,
                                                stateTrackingMethod: .OnNothing,
                                                methodTracking: .Manual)
    }
    
    func startTrackingWithConfigurationFile(pathForFile:String?,
                                            stateTracking:TrackingTypes?,
                                            stateTrackingMethod:StateTrackingMethod?,
                                            methodTracking:TrackingTypes?) -> Void {
        
        self.configurationFilePath = pathForFile
        self.stateTrackingMethod = stateTrackingMethod
        
        self.configParser = nil
        self.configParser = ATTConfigParser(configurations: self.configurationDictionary() as? Dictionary<String, AnyObject>)
        
        self.configureSwizzling(stateTracking: stateTracking,
                                stateTrackingMethod: stateTrackingMethod,
                                methodTracking: methodTracking)
    }
   
    func startTrackingWithConfiguration(configuration:Dictionary<String, AnyObject>?) -> Void {
        self.startTrackingWithConfiguration(configuration: configuration,
                                            stateTracking: .Manual,
                                            stateTrackingMethod: .OnNothing,
                                            methodTracking: .Manual)
    }
    
    func startTrackingWithConfiguration(configuration:Dictionary<String, AnyObject>?,
                                        stateTracking:TrackingTypes?,
                                        stateTrackingMethod:StateTrackingMethod?,
                                        methodTracking:TrackingTypes?) -> Void {
        
        self.stateTrackingMethod = stateTrackingMethod
        self.configParser = nil
        self.configParser = ATTConfigParser(configurations: configuration)
        
        self.configureSwizzling(stateTracking: stateTracking,
                                stateTrackingMethod: stateTrackingMethod,
                                methodTracking: methodTracking)
    }
    
    /// Can be called manually for Manual event tracking
    /// **customArguments** is used when an object requires to trigger event with dynamic values
    func registerForTracking(appSpecificKeyword:String?,
                             customArguments:Dictionary<String, AnyObject>?) -> Void {
        
        self.trackConfigurationForClass(aClass: nil,
                                        selector: nil,
                                        stateType: .Event,
                                        appSpecificKeyword: appSpecificKeyword,
                                        customArguments: customArguments)
    }
    
    /// Used to receive the crashlog events
    /// Must be called once inside AppDelegate's **applicationDidBecomeActive**
    func registerForCrashLogging() -> Void {
        if let crashLogData = self.readLastSavedCrashLog() {
            
            if (crashLogData as String).characters.count > 0 {
                var notificationObject = [String: AnyObject]()
                
                notificationObject["type"] = "CrashLogTracking" as AnyObject?
                notificationObject["crash_report"] = crashLogData as AnyObject?
                notificationObject["app_info"] = self.appInfo() as AnyObject?
                
                NotificationCenter.default.post(name: NSNotification.Name(rawValue: ATTTrackingHelper.CrashTrackingNotification),
                                                object: notificationObject)
            }
        }
    }
    
    // MARK: Private methods
    private func configureSwizzling(stateTracking:TrackingTypes?,
                                    stateTrackingMethod:StateTrackingMethod?,
                                    methodTracking:TrackingTypes?) -> Void {
        
        if stateTracking == .Automatic && stateTrackingMethod != .OnNothing {
            self.swizzileLifecycleMethodImplementation()
        }
        
        if methodTracking == .Automatic {
            self.swizzileCustomMethods()
        }
    }
    
    // Triggered for state changes
    private func triggerEventForTheVisibleViewController(viewController:UIViewController) -> Void {
        self.trackConfigurationForClass(aClass: viewController.classForCoder,
                                        selector: self.stateChangeTrackingSelector,
                                        stateType: .State,
                                        appSpecificKeyword: nil,
                                        customArguments: nil)
    }
    
    // Triggered for method invocation
    private func triggerEventForTheVisibleViewController(originalClass:AnyClass?, selector:Selector?) -> Void {
        self.trackConfigurationForClass(aClass: originalClass,
                                        selector: selector,
                                        stateType: .Event,
                                        appSpecificKeyword: nil,
                                        customArguments: nil)
    }
    
    // Looping through the configuration to find out the matching paramters and values
    private func trackConfigurationForClass(aClass:AnyClass?,
                                            selector:Selector?,
                                            stateType:StateTypes?,
                                            appSpecificKeyword:String?,
                                            customArguments:Dictionary<String, AnyObject>?) -> Void {
        
        let paramters = self.configurationForClass(aClass: aClass,
                                                   selector: selector,
                                                   stateType: stateType,
                                                   appSpecificKeyword: appSpecificKeyword)
        
        if paramters != nil && (paramters?.count)! > 0 {
            self.registeredAnEvent(configuration: paramters,
                                   customArguments: customArguments)
        }
    }
    
    // Parsing the Configuration file
    private func configurationDictionary() -> NSDictionary? {
        let resourcePath = self.configurationFilePath
        let resourceData = NSDictionary(contentsOfFile: resourcePath!)
        
        return resourceData
    }
    
    private func configurationForClass(aClass:AnyClass?,
                                       selector:Selector?,
                                       stateType:StateTypes?,
                                       appSpecificKeyword:String?) -> Array<AnyObject>? {
        var state = ""
        if stateType == .State {
            state = ATTConfigConstants.AgentKeyTypeState
        } else {
            state = ATTConfigConstants.AgentKeyTypeEvent
        }
        
        let resultConfig = (self.configParser?.findConfigurationForClass(aClass: aClass,
                                                                         selector: selector,
                                                                         stateType: state,
                                                                         appSpecificKeyword: appSpecificKeyword))! as Array<AnyObject>
        return resultConfig
    }
    
    // Triggering a Notification, whenever it finds a matching configuration
    private func registeredAnEvent(configuration:Array<AnyObject>?,
                                   customArguments:Dictionary<String, AnyObject>?) -> Void {
        
        var notificationObject = [String: AnyObject]()

        notificationObject["configuration"] = configuration as AnyObject?
        notificationObject["custom_arguments"] = customArguments as AnyObject?
        notificationObject["app_info"] = self.appInfo() as AnyObject?
        
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: ATTTrackingHelper.TrackingNotification),
                                        object: notificationObject)
    }
    
    private func appInfo() -> Dictionary<String, AnyObject>? {
        let dictionary = Bundle.main.infoDictionary
        let version = dictionary?["CFBundleShortVersionString"] as? String
        let build = dictionary?["CFBundleVersion"] as? String
        let appName = dictionary?["CFBundleName"] as? String
        let bundleID = Bundle.main.bundleIdentifier
        
        var appInfoDictionary = [String: AnyObject]()
        
        appInfoDictionary["version"] = version as AnyObject?
        appInfoDictionary["build"] = build as AnyObject?
        appInfoDictionary["bundleID"] = bundleID as AnyObject?
        appInfoDictionary["app_name"] = appName as AnyObject?
        
        return appInfoDictionary
    }
    
    // MARK: Crashlog file manipulations
    private func readLastSavedCrashLog() -> String? {
        let fileName = self.fileNameForLogFileOn(onDate: Date())
        let filePath = self.cacheDirectory.appending(fileName!)
        var dataString:String = String()
        
        self.clearYesterdaysCrashLog()
        
        if self.fileManager.fileExists(atPath: filePath) {
            if let crashLogData = NSData(contentsOfFile: filePath) {
                dataString = NSString(data: crashLogData as Data, encoding:String.Encoding.utf8.rawValue) as! String
            }
        }
        
        // To avoid complexity in reading and parsing the crash log, keeping only the last crash information
        // For allowing this, previous crash logs are deleted after reading
        self.removeCrashLogOn(onDate: Date())
        self.createCrashLogFile(atPath: filePath)
        return dataString
    }
    
    // Log files are being created with current date as its name
    // In odrder to prevent dumping of logs, will be removing previous log files
    // Date is used in order to extend the feature of multiple crash logs
    private func clearYesterdaysCrashLog() -> Void {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())
        
        self.removeCrashLogOn(onDate: yesterday)
    }
    
    private func createCrashLogFile(atPath: String) -> Void {
        freopen(atPath.cString(using: String.Encoding.utf8), "a+", stderr)
    }
    
    private func removeCrashLogOn(onDate: Date?) -> Void {
        let filePath = self.cacheDirectory.appending(self.fileNameForLogFileOn(onDate: onDate)!)
        try?self.fileManager.removeItem(atPath: filePath)
    }
    
    private func fileNameForLogFileOn(onDate:Date?) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MM-yyyy"
        
        return "CrashlogAsOn-".appending(formatter.string(from: onDate!).appending(".log"))
    }
    
    // MARK: Automatic screen change tracking
    // MUST BE CALLED ONLY ONCE
    private func swizzileLifecycleMethodImplementation() -> Void {
        if self.stateTrackingMethod == .OnViewDidLoad {
            self.stateChangeTrackingSelector = #selector(UIViewController.viewDidLoad)
        }
        
        if self.stateTrackingMethod == .OnViewWillAppear {
            self.stateChangeTrackingSelector = #selector(UIViewController.viewWillAppear(_:))
        }
        
        if self.stateTrackingMethod == .OnViewDidAppear {
            self.stateChangeTrackingSelector = #selector(UIViewController.viewDidAppear(_:))
        }
        
        let originalClass:AnyClass = UIViewController.self
        let swizzilableClass = ATTTrackingHelper.self
        
        let originalMethod = class_getInstanceMethod(originalClass, self.stateChangeTrackingSelector!)
        let swizzledMethod = class_getInstanceMethod(swizzilableClass, #selector(ATTTrackingHelper.trackScreenChange))
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
    
    // Swizzled method which will be replacing the original ViewController methods which is mentioned in the autoScreenTrackingType
    func trackScreenChange() -> Void {
        // Here self refers to the UIViewController, self.autoTrackScreenChanges() will crash
        if !(self as NSObject is UITabBarController) && !(self as NSObject is UINavigationController) {
            // Lifecycle methods will be triggered to UITabBarController and UINavigationController
            // So skipping their lifecycle implementations and considering only UIViewController lifecycles
            ATTTrackingHelper.helper.autoTrackScreenChanges(viewController: self)
        }
    }
    
    func autoTrackScreenChanges(viewController:NSObject?) -> Void {
        if let topViewController = viewController as? UIViewController {
            self.triggerEventForTheVisibleViewController(viewController: topViewController)
        }
    }
    
    // MARK: Automatic function call tracking
    // MUST BE CALLED ONLY ONCE
    private func swizzileCustomMethods() -> Void {
        let originalClass:AnyClass = UIApplication.self
        let swizzilableClass = ATTTrackingHelper.self
        
        let originalMethod = class_getInstanceMethod(originalClass,
                                                     #selector(UIApplication.sendAction(_:to:from:for:)))
        let swizzledMethod = class_getInstanceMethod(swizzilableClass,
                                                     #selector(ATTTrackingHelper.trackMethodInvocation(_:to:from:for:)))
        
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
    
    // Swizzled method which will be replacing the original UIApplication's sendAction method
    func trackMethodInvocation(_ action: Selector, to target: Any?, from sender: Any?, for event: UIEvent?) -> Void {
        if let originalObject = target as? NSObject {
            let className = "\(originalObject.classForCoder)" as String
            ATTTrackingHelper.helper.autoTrackMethodInvocationForClass(originalClassName: className, selector: action)
        }
        
        // Inorder to call the original implementation, perform the 3 below steps
        ATTTrackingHelper.helper.swizzileCustomMethods()
        // 1. Calling the swizzileCustomMethods() again will re-swizzile to original implementation
        UIApplication.shared.sendAction(action, to: target, from: sender, for: event)
        // 2. Now call the original class's original method
        ATTTrackingHelper.helper.swizzileCustomMethods()
        // 3. Swizzile the method again for receiving the next event
    }
    
    func autoTrackMethodInvocationForClass(originalClassName:String?, selector:Selector?) -> Void {
        let aClassName = NSStringFromClass(self.classForCoder)
        let nameSpace = aClassName.components(separatedBy: ".")
        let prefix = nameSpace[0] as String
        let fullClassName = "\(prefix).\(originalClassName!)"
        let originalClass:AnyClass = NSClassFromString(fullClassName)! as AnyClass
        
        self.triggerEventForTheVisibleViewController(originalClass: originalClass, selector: selector)
    }
}
