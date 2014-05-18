//
//  Math.h
//  Firechat
//
//  Created by Ethan Sherr on 3/3/14.
//  Copyright (c) 2014 Buildco. All rights reserved.
//

#import <Foundation/Foundation.h>

#define ARC4RANDOM_MAX 0x100000000

@protocol Math <NSObject>

static inline NSInteger esRandomNumberIn(int min, int max)
{
    return min + arc4random() % (max - min);
}
static inline float esRandomFloatIn(float min, float max)
{
    float f =  ((double)arc4random() / ARC4RANDOM_MAX)*(max-min)+min;
    return f;
}



/*
 call it like this:
 
 uint32_t bigIdentifier = [0, 4294967295] (inclusive), 4294967296 = 2^32
 
 
 uint16_t major, minor;
 esDecomposeIdToMajorMinor(i, &major, &minor);
 //now major and minor are values!
 
 */
static inline void esDecomposeIdToMajorMinor(uint32_t identifier, uint16_t *major, uint16_t *minor)
{
    
    unsigned char byte4 = (uint)(identifier>>24);
    unsigned char byte3 = (uint)(identifier>>16);
    unsigned char byte2 = (uint)(identifier>>8);
    unsigned char byte1 = (uint)(identifier>>0);
    
    
    *major = byte1 + (byte2<<8);
    *minor = byte3 + (byte4<<8);
}



/*
 call it like this:
 
 uint16_t major = //[0, 65535] (inclusive), 2^16 = 65536
 uint16_t minor = //[0, 65535]
 
 uint32_t identifier;
 esRecomposeMajorMinorToId(major, minor, &identifier);
 //now identifier is value
 */
static inline void esRecomposeMajorMinorToId(uint16_t major, uint16_t minor, uint32_t *identifier)
{
    unsigned char byte2 = major>>8;
    unsigned char byte1 = major>>0;
    
    unsigned char byte4 = minor>>8;
    unsigned char byte3 = minor>>0;
    
    *identifier = byte1 + (byte2<<8) + (byte3<<16) + (byte4<<24);
}



@end
