//
//  UIApplication+JTSImageViewController.m
//  Riposte
//
//  Created by Jared on 4/3/14.
//  Copyright (c) 2014 Riposte LLC. All rights reserved.
//

#import "UIApplication+JTSImageViewController.h"

@implementation UIApplication (JTSImageViewController)

- (BOOL)jts_usesViewControllerBasedStatusBarAppearance {
    static dispatch_once_t once;
    static BOOL viewControllerBased;
    dispatch_once(&once, ^ {
        NSString *key = @"UIViewControllerBasedStatusBarAppearance";
        id object = [[NSBundle mainBundle] objectForInfoDictionaryKey:key];
        if (!object) {
            viewControllerBased = YES;
        } else {
            viewControllerBased = [object boolValue];
        }
    });
    return viewControllerBased;
}

@end
