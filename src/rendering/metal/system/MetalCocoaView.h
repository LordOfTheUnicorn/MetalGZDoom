//
//  MetalCocoaView.h
//  GZDoom
//
//  Created by Евгений Григорчук on 19.02.2020.
//

#ifndef MetalCocoaView_h
#define MetalCocoaView_h
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

@interface MetalCocoaView : NSView <NSWindowDelegate>
{
    NSCursor* m_cursor;
    CAMetalLayer *metalLayer;
    NSString *str;
}

- (void)setCursor:(NSCursor*)cursor;
- (id<CAMetalDrawable>)getDrawable;
- (id)initWithFrame:(NSRect)FrameRect device:(id<MTLDevice>)device vsync:(bool)vsync Str:(NSString*)Str;
@end

#endif /* MetalCocoaView_h */
