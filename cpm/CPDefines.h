//
//  CPDefines.h
//  cpm
//
//  Created by Alexander Zielenski on 3/3/15.
//  Copyright (c) 2015 Chariz Team. All rights reserved.
//

#ifndef cpm_CPDefines_h
#define cpm_CPDefines_h

#define LOCALSTORAGE_PATH @"/usr/local/cpm"
#define IDENTIFIER @"io.chariz.cpm"
#define CPMERRORDOMAIN @"io.chariz.cpm.error"

typedef NS_ENUM(NSUInteger, CPMErrorCode) {
    CPMErrorUnacceptableStatusCode = 0,
    CPMErrorDatabase               = 1,
    CPMErrorInvalidFormat          = 2,
    CPMErrorDecompression          = 3
};

#define CPMErrorStatusCodeKey @"statusCode"

#endif
