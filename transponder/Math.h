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

@end
