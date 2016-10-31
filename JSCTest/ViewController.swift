//
//  ViewController.swift
//  JSCTest
//
//  Created by Pavel Zdeněk on 26.O.16.
//  Copyright © 2016 BrowserTech. All rights reserved.
//

import UIKit
import JavaScriptCore

class ViewController: UIViewController {

  let jscontext = JSContext()

  enum MainThreadBlockingMode {
    case NotBlocking // both loops running dispatched
    case FromInside // only the invocations inside JS running
    case FromOutside // only the invocations in native code running
  }

  let blockingMode = MainThreadBlockingMode.FromOutside

  override func viewDidLoad() {
    super.viewDidLoad()
    jscontext?.exceptionHandler = { context, exception in
      let exceptionString = exception?.toString() ?? "Unknown"
      NSLog("EXCEPTION %@", exceptionString)
    }
    let jslogging: @convention(block) (String) -> Void = { input in
      NSLog("JSCLOG %@", input)
    }
    let setTimeout: @convention(block) (JSValue, JSValue) -> Void = { callback, maybeMillis in
      if callback.isUndefined || callback.isNull {
        return
      }
      guard let millis: Int = {
        if maybeMillis.isUndefined {
          // Mozilla doc: If this parameter is omitted, a value of 0 is used
          return 0
        }
        if maybeMillis.isNull || !maybeMillis.isNumber {
          // But if not omitted, must be a number
          return nil
        }
        return maybeMillis.toNumber().intValue
      }() else {
        return
      }
      if millis > 0 {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(millis)) {
          let _ = callback.call(withArguments: [])
        }
      } else {
        DispatchQueue.main.async {
          let _ = callback.call(withArguments: [])
        }
      }
    }
    jscontext?.setObject(unsafeBitCast(jslogging, to: AnyObject.self), forKeyedSubscript: "jslogging" as NSString)
    jscontext?.setObject(unsafeBitCast(setTimeout, to: AnyObject.self), forKeyedSubscript: "setTimeout" as NSString)
  }

  override func viewDidAppear(_ animated: Bool) {
    let insideLoopCode: String = { blockingMode in
      switch blockingMode {
      case .FromInside:
        // must be dispatched once to allow finishing the jscontext invocation call
        // but then blocks tightly
        return "function x(i){setTimeout(function(){for(;;){jslogging('inside '+i);i++}})}"
      default:
        // async recursion - every call dispatched
        return "function x(i){jslogging('inside '+i);setTimeout(function(){x(i+1)})}"
      }
    }(blockingMode)
    let _ = jscontext?.evaluateScript(insideLoopCode)
    let _ = jscontext?.objectForKeyedSubscript("x")?.call(withArguments: [0])
    if blockingMode == .FromOutside {
      // block tightly
      var i = 0
      while true {
        outsideTick(asyncRecurse: false, i)
        i += 1
      }
    } else {
      // async
      outsideTick(asyncRecurse: true, 0)
    }
  }

  func outsideTick(asyncRecurse: Bool, _ i: Int) {
    let _ = jscontext?.evaluateScript("jslogging('outside '+\(i))")
    if asyncRecurse {
      DispatchQueue.main.async {
        self.outsideTick(asyncRecurse: true, i+1)
      }
    }
  }

  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
  }
}

