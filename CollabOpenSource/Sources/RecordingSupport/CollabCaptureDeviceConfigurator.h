#ifndef CollabCaptureDeviceConfigurator_h
#define CollabCaptureDeviceConfigurator_h

// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>

@class AVCaptureDevice;
@class AVCaptureDeviceFormat;

NS_ASSUME_NONNULL_BEGIN

void collabConfigureDevice(AVCaptureDevice *device,
                           AVCaptureDeviceFormat *format,
                           CMTime duration);

NS_ASSUME_NONNULL_END

#endif /* CollabCaptureDeviceConfigurator_h */
