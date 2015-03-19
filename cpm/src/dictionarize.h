//
//  dictionarize.h
//  cpm
//
//  Created by Alexander Zielenski on 3/18/15.
//  Copyright (c) 2015 Chariz Team. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <FMDatabase.h>

#ifndef __cpm__dictionarize__
#define __cpm__dictionarize__

NSDictionary *dictionarize(NSString *data, FMDatabase *db, NSString *table);

#endif /* defined(__cpm__dictionarize__) */
