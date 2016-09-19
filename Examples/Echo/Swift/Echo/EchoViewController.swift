/*
 *
 * Copyright 2016, Google Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *     * Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 * copyright notice, this list of conditions and the following disclaimer
 * in the documentation and/or other materials provided with the
 * distribution.
 *     * Neither the name of Google Inc. nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */
import AppKit
import gRPC
import QuickProto

class EchoViewController : NSViewController, NSTextFieldDelegate {
  @IBOutlet weak var messageField: NSTextField!
  @IBOutlet weak var outputField: NSTextField!
  @IBOutlet weak var addressField: NSTextField!
  @IBOutlet weak var streamingButton: NSButton!
  @IBOutlet weak var TLSButton: NSButton!

  private var fileDescriptorSet : FileDescriptorSet
  private var client: Client?
  private var call: Call?
  private var nowStreaming = false

  required init?(coder:NSCoder) {
    fileDescriptorSet = FileDescriptorSet(filename: "echo.out")
    super.init(coder:coder)
  }

  var enabled = false

  @IBAction func messageReturnPressed(sender: NSTextField) {
    if enabled {
      callServer(address:addressField.stringValue)
    }
  }

  @IBAction func addressReturnPressed(sender: NSTextField) {
    if (nowStreaming) {
      self.sendClose()
    }
  }

  @IBAction func buttonValueChanged(sender: NSButton) {
    if (nowStreaming && (sender.intValue == 0)) {
      self.sendClose()
    }
  }

  override func viewDidLoad() {
    gRPC.initialize()
  }

  override func viewDidAppear() {
    // prevent the UI from trying to send messages until gRPC is initialized
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      self.enabled = true
    }
  }

  func createClient(address: String, host: String) {
    if (TLSButton.intValue == 0) {
      client = Client(address:address)
    } else {
      let certificateURL = Bundle.main.url(forResource: "ssl", withExtension: "crt")!
      let certificates = try! String(contentsOf: certificateURL)
      client = Client(address:address, certificates:certificates, host:host)
    }
  }

  func callServer(address:String) {
    let requestHost = "example.com"
    let requestMetadata = Metadata(["x-goog-api-key":"YOUR_API_KEY",
                                    "x-ios-bundle-identifier":Bundle.main.bundleIdentifier!])

    if (self.streamingButton.intValue == 0) {
      // NONSTREAMING
      if let requestMessage = self.fileDescriptorSet.createMessage("EchoRequest") {
        requestMessage.addField("text", value:self.messageField.stringValue)
        let requestMessageData = requestMessage.data()
        createClient(address:address, host:requestHost)
        guard let client = client else {
          return
        }
        call = client.createCall(host: requestHost,
                                 method: "/echo.Echo/Get",
                                 timeout: 30.0)
        guard let call = call else {
          return
        }
        _ = call.performNonStreamingCall(messageData: requestMessageData,
                                         metadata: requestMetadata)
        { (status, statusDetails, messageData, initialMetadata, trailingMetadata) in
          print("Received status: \(status): \(statusDetails)")
          if let messageData = messageData,
            let responseMessage = self.fileDescriptorSet.readMessage("EchoResponse",
                                                                     data:messageData) {
            responseMessage.forOneField("text") {(field) in
              DispatchQueue.main.async {
                self.outputField.stringValue = field.string()
              }
            }
          } else {
            DispatchQueue.main.async {
              self.outputField.stringValue = "No message received. gRPC Status \(status): \(statusDetails)"
            }
          }
        }
      }
    }
    else {
      // STREAMING
      if (!nowStreaming) {
        createClient(address:address, host:requestHost)
        guard let client = client else {
          return
        }
        call = client.createCall(host: requestHost,
                                 method: "/echo.Echo/Update",
                                 timeout: 30.0)
        guard let call = call else {
          return
        }
        _ = call.start(metadata:requestMetadata)
        self.receiveMessage()
        nowStreaming = true
      }
      self.sendMessage()
    }
  }

  func sendMessage() {
    let requestMessage = self.fileDescriptorSet.createMessage("EchoRequest")!
    requestMessage.addField("text", value:self.messageField.stringValue)
    let messageData = requestMessage.data()
    if let call = call {
      call.sendMessage(data:messageData)
    }
  }

  func receiveMessage() {
    guard let call = call else {
      return
    }
    _ = call.receiveMessage() {(data) in
      guard let responseMessage = self.fileDescriptorSet.readMessage("EchoResponse", data:data)
        else {
          return // this stops receiving
      }
      responseMessage.forOneField("text") {(field) in
        DispatchQueue.main.async {
          self.outputField.stringValue = field.string()
        }
        self.receiveMessage()
      }
    }
  }

  func sendClose() {
    guard let call = call else {
      return
    }
    _ = call.close() {
      self.nowStreaming = false
    }
  }
}