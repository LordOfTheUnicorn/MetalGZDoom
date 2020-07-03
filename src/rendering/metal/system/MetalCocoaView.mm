//
//  MetalCocoaView.cpp
//  GZDoom
//
//  Created by Евгений Григорчук on 19.02.2020.
//

#include "MetalCocoaView.h"

@implementation MetalCocoaView

- (void)drawRect:(NSRect)dirtyRect
{
    [NSColor.blackColor setFill];
    NSRectFill(dirtyRect);
}

- (void)resetCursorRects
{
    [super resetCursorRects];

    NSCursor* const cursor = nil == m_cursor
        ? [NSCursor arrowCursor]
        : m_cursor;

    [self addCursorRect:[self bounds]
                 cursor:cursor];
}

- (void)setCursor:(NSCursor*)cursor
{
    m_cursor = cursor;
}

-(id)initWithFrame:(NSRect)FrameRect device:(id<MTLDevice>)device vsync:(bool)vsync Str:(NSString*)Str
{
    self = [super initWithFrame:FrameRect];
    self.wantsLayer = YES;
    
    metalLayer = [CAMetalLayer layer];
    metalLayer.device =  device;
    metalLayer.framebufferOnly = YES; //todo: optimized way
    metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    metalLayer.wantsExtendedDynamicRangeContent = false;
    metalLayer.drawableSize = CGSizeMake(self.frame.size.width, self.frame.size.height);
    metalLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    metalLayer.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3); // TEMPORARY
    if (@available(macOS 10.13, *)) {
        metalLayer.displaySyncEnabled = vsync;
    }
    self.layer = metalLayer;
    str = Str;
    NSUserDefaults *StandardDefaults = [NSUserDefaults standardUserDefaults];
    
    NSTrackingArea* trackingArea = [[[NSTrackingArea alloc] initWithRect: self.bounds
                                                                 options: ( NSTrackingCursorUpdate | NSTrackingActiveInKeyWindow )
                                                                   owner:self userInfo:nil] autorelease];
    [self addTrackingArea:trackingArea];
    [self setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
    
    return self;
}

-(id<CAMetalDrawable>)getDrawable
{
    return metalLayer.nextDrawable;
}

@end
