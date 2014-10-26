//
//  JTSImageInfo.m
//  
//
//  Created by Jared Sinclair on 3/2/14.
//  Copyright (c) 2014 Nice Boy LLC. All rights reserved.
//

#import "JTSImageInfo.h"

@implementation JTSImageInfo


- (NSString *)displayableTitleAltTextSummary {
    NSString *text = nil;
    if (self.title.length) {
        text = [NSString stringWithFormat:@"%@", self.title];
    }
    else if (self.altText.length) {
        text = [NSString stringWithFormat:@"%@", self.altText];
    }
    return text;
}

- (NSString *)combinedTitleAndAltText {
    NSMutableString *text = [[NSMutableString alloc] init];
    if (self.title.length) {
        [text appendFormat:@"“%@”", self.title];
    }
    if (self.altText.length) {
        if ([self.altText isEqualToString:self.title] == NO) {
            [text appendFormat:@"\n\n— — —\n\n%@", self.altText];
        }
    }
    return text;
}

- (NSMutableDictionary *)userInfo {
    if (_userInfo == nil) {
        _userInfo = [[NSMutableDictionary alloc] init];
    }
    return _userInfo;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"\
            %@ %p \n\
            imageURL: %@ \n\
            referenceRect: (%g, %g) (%g, %g)",
            
            NSStringFromClass(self.class), self,
            self.imageURL,
            self.referenceRect.origin.x, self.referenceRect.origin.y, self.referenceRect.size.width, self.referenceRect.size.height
            ];
}

- (CGPoint)referenceRectCenter {
    return CGPointMake(self.referenceRect.origin.x + self.referenceRect.size.width/2.0f,
                       self.referenceRect.origin.y + self.referenceRect.size.height/2.0f);
}

@end





