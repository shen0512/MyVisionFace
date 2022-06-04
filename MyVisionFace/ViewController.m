//
//  ViewController.m
//  MyVisionFace
//
//  Created by Shen on 2022/4/6.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>

@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic) int captureWidth;
@property (nonatomic) int captureHeight;
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) VNImageBasedRequest *detectRequest;

@property (nonatomic) BOOL faceDetectDone;
@property (weak, nonatomic) IBOutlet UIImageView *imageView;
@property (weak, nonatomic) IBOutlet UIImageView *drawView;
@property (nonatomic) BOOL frontLens;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    _faceDetectDone = YES;
    [self visionFaceInit];
    [self cameraInit];
    
}

# pragma mark init
- (void)cameraInit{
    /**
     @biref camera init
     */
    AVCaptureDeviceInput *input;
    if(_frontLens){
        AVCaptureDevice *captureDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionFront];
        input = [AVCaptureDeviceInput deviceInputWithDevice:captureDevice error:nil];
        
        _imageView.transform = CGAffineTransformMakeScale(-1, 1);
        _drawView.transform = CGAffineTransformMakeScale(-1, 1);
    }else{
        AVCaptureDevice *captureDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
        input = [AVCaptureDeviceInput deviceInputWithDevice:captureDevice error:nil];
        
        _imageView.transform = CGAffineTransformMakeScale(1, 1);
        _drawView.transform = CGAffineTransformMakeScale(1, 1);
    }
    
    // Initialize the captureSession object.
    _captureSession = [[AVCaptureSession alloc] init];
    // Set the input device on the capture session.
    [_captureSession addInput:input];
    [_captureSession setSessionPreset:AVCaptureSessionPreset1920x1080];
    _captureHeight = 1920;
    _captureWidth = 1080;
    
    // Initialize a AVCaptureMetadataOutput object and set it as the output device to the capture session.
    AVCaptureVideoDataOutput *captureVideoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    [_captureSession addOutput:captureVideoDataOutput];
    
    AVCaptureConnection *connection = [captureVideoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    [connection setPreferredVideoStabilizationMode:AVCaptureVideoStabilizationModeStandard];
    
    // Create a new serial dispatch queue.
    [captureVideoDataOutput setSampleBufferDelegate:self queue:dispatch_queue_create("myQueue", NULL)];
    
    // start
    [_captureSession startRunning];
}

- (void)visionFaceInit{
    /**
     @brief vison init
     
     */
    // only bounding box
//    _detectRequest = [[VNDetectFaceRectanglesRequest alloc] initWithCompletionHandler:^(VNRequest *request, NSError * _Nullable error) {
//        NSArray *observations = request.results;
//        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(){
//
//            dispatch_sync(dispatch_get_main_queue(), ^(){
//                _drawView.image = nil;
//            });
//            UIImage *tmpCanvas = nil;
//            if([observations count] > 0){
//                VNFaceObservation *face = observations[0];
//
//                tmpCanvas = [self createCanvas];
//                CGRect rect = [self visonBbox2UIImageBbox:[face boundingBox]];
//                tmpCanvas = [self drawRect:tmpCanvas :rect];
//            }
//
//            dispatch_async(dispatch_get_main_queue(),^(){
//                _drawView.image = tmpCanvas;
//            });
//
//            _faceDetectDone = YES;
//        });
//    }];
    
    // bounding box + landmark
    _detectRequest = [[VNDetectFaceLandmarksRequest alloc] initWithCompletionHandler:^(VNRequest *request, NSError * _Nullable error) {
        NSArray *observations = request.results;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(){

            dispatch_sync(dispatch_get_main_queue(), ^(){
                _drawView.image = nil;
            });

            UIImage *tmpCanvas = nil;
            if([observations count] > 0){
                // only draw a face
                VNFaceObservation *face = observations[0];
                VNFaceLandmarkRegion2D* landmarks = face.landmarks.allPoints;

                tmpCanvas = [self createCanvas];
                CGRect rect = [face boundingBox];

                // face bounding box
                tmpCanvas = [self drawRect:tmpCanvas :[self visonBbox2UIImageBbox:rect]];

                // face landmark
                for(int i=0; i<[landmarks pointCount]; i++){
                    CGPoint tmpPoint = [self visionPoint2UIImagePoint:rect :landmarks.normalizedPoints[i]];
                    tmpCanvas = [self drawPoint:tmpCanvas :CGPointMake(tmpPoint.x, tmpPoint.y)];
                }
            }

            // update drawView
            dispatch_sync(dispatch_get_main_queue(), ^(){
                _drawView.image = tmpCanvas;
            });

            _faceDetectDone = YES;
        });
    }];

}

# pragma mark delegate
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
    
    dispatch_sync(dispatch_get_main_queue(), ^(){
        
        CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
        CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];

        CIContext *temporaryContext = [CIContext contextWithOptions:nil];
        CGImageRef videoImage = [temporaryContext createCGImage:ciImage
                                                       fromRect:CGRectMake(0, 0, CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer))];
            
        UIImage *uiImage = [UIImage imageWithCGImage:videoImage];
        CGImageRelease(videoImage);
        
        _imageView.image = uiImage;
        
        [self faceDetection:uiImage];
    });
}

-(void)faceDetection:(UIImage*)image{
    /**
     @brief face detection
     @param image
     */
    if(_faceDetectDone == YES){
        _faceDetectDone = NO;
        // 轉換CIImage
        CIImage *convertImage = [[CIImage alloc] initWithImage:image];
        
        // 創建處理 RequestHandler
        VNImageRequestHandler *detectRequestHandler = [[VNImageRequestHandler alloc] initWithCIImage:convertImage options:@{}];

        // 發送識別請求
        NSError *err;
        [detectRequestHandler performRequests:@[_detectRequest] error:&err];
        
        if(err!=nil){
            NSLog(@"error: %@", err);
        }
    }
    
}

# pragma mark other

- (IBAction)changeLens:(UISwitch *)sender {
    if([_captureSession isRunning]){
        [_captureSession stopRunning];
    }
    
    if(sender.isOn){
        _frontLens = YES;
    }else{
        _frontLens = NO;
    }
    
    [self cameraInit];
}

-(CVPixelBufferRef)pixelBufferFromCGImage: (CGImageRef)image{
    NSDictionary *options = @{
                              (NSString*)kCVPixelBufferCGImageCompatibilityKey : @YES,
                              (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
                              };

    CVPixelBufferRef pxbuffer = NULL;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, CGImageGetWidth(image),
                        CGImageGetHeight(image), kCVPixelFormatType_32ARGB, (__bridge CFDictionaryRef) options,
                        &pxbuffer);
    if (status!=kCVReturnSuccess) {
        NSLog(@"Operation failed");
    }
    NSParameterAssert(status == kCVReturnSuccess && pxbuffer != NULL);

    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);

    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, CGImageGetWidth(image),
                                                 CGImageGetHeight(image), 8, 4*CGImageGetWidth(image), rgbColorSpace,
                                                 kCGImageAlphaNoneSkipFirst);
    NSParameterAssert(context);

    CGContextConcatCTM(context, CGAffineTransformMakeRotation(0));
    CGAffineTransform flipVertical = CGAffineTransformMake(1, 0, 0, -1, 0, CGImageGetHeight(image) );
    CGContextConcatCTM(context, flipVertical);
    CGAffineTransform flipHorizontal = CGAffineTransformMake(-1.0, 0.0, 0.0, 1.0, CGImageGetWidth(image), 0.0 );
    CGContextConcatCTM(context, flipHorizontal);

    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image),
                                           CGImageGetHeight(image)), image);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);

    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    return pxbuffer;
}

-(CGRect)visonBbox2UIImageBbox:(CGRect)bbox{
    /**
     @brief Vision 座標轉換成 UIImage 座標
     @param bbox vision bounding box result
     @return 轉換後的結果
     */
    CGFloat tlx = bbox.origin.x*_captureWidth;
    CGFloat tly = bbox.origin.y*_captureHeight;
    CGFloat width = bbox.size.width*_captureWidth;
    CGFloat height = bbox.size.height*_captureHeight;
    
    return CGRectMake(tlx, _captureHeight-height-tly, width, height);
}

-(CGPoint)visionPoint2UIImagePoint:(CGRect)bbox :(CGPoint)point{
    /**
     @brief Vision 座標轉換成 UIImage 座標
     ＠param bbox vision bounding box
     @param point vision landmark result
     @return 轉換後的結果
     */
    float x = (point.x*bbox.size.width+bbox.origin.x)*_captureWidth;
    float y = (1-(point.y*bbox.size.height+bbox.origin.y))*_captureHeight;
    
    return CGPointMake(x, y);
    
}

-(UIImage*)createCanvas{
    /**
     @brief 建立透明畫布
     @return 透明畫布
     */
    UIGraphicsBeginImageContext(CGSizeMake(_captureWidth, _captureHeight));
    CGContextRef context = UIGraphicsGetCurrentContext();
    UIColor *bgColor = [UIColor colorWithWhite:1 alpha:1];
    CGContextSetFillColorWithColor(context, bgColor.CGColor);
    
    UIImage *result=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
        
    return result;
}

-(UIImage*)drawRect:(UIImage*)canvas :(CGRect)rect{
    /**
     @brief 將矩形在畫布上
     @param canvas 畫布
     @param rect 矩形
     @return 畫矩形後的圖片
     */
    UIGraphicsBeginImageContext(CGSizeMake(_captureWidth, _captureHeight));
    
    // 設定透明背景
    CGContextRef context = UIGraphicsGetCurrentContext();
    [canvas drawAtPoint:CGPointMake(0, 0)];

    // 設定矩形線條寬度及線條顏色
    [[UIColor redColor] setStroke];
    CGContextSetLineWidth(context, 5);
    CGContextAddRect(context, rect);
    CGContextDrawPath(context, kCGPathStroke);
    
    // 結束
    UIImage *result=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return result;
}

-(UIImage*)drawPoint:(UIImage*)canvas :(CGPoint)point{
    /**
     @brief 將點畫在畫布上
     @param canvas 畫布
     @param point 座標點
     @return 畫座標點後的圖片
     */
    
    UIGraphicsBeginImageContext(CGSizeMake(_captureWidth, _captureHeight));
    
    // 設定透明背景
    CGContextRef context = UIGraphicsGetCurrentContext();
    [canvas drawAtPoint:CGPointMake(0, 0)];
    
    // 設定矩形線條寬度及線條顏色
    [[UIColor greenColor] setStroke];
    CGContextSetLineWidth(context, 10);
    CGContextAddRect(context, CGRectMake(point.x-5, point.y-5, 10, 10));
    CGContextDrawPath(context, kCGPathFillStroke);
    
    // 結束
    UIImage *result=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    
    return result;
}

@end
