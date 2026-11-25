// Скрытое мод-меню: 3 пальца x 3 тапа открывают, крестик закрывает.
// Сборка: Theos (см. Makefile), потом вшить dylib в IPA через Sideloadly.
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>

// ====== Флаги, которые читают игровые хуки ======
volatile BOOL gAutoSprint = NO;
volatile BOOL gNoHurtCam  = NO;
volatile BOOL gShowHitbox = NO;

// ====== Игровые хуки (ЗАПОЛНИТЬ) ======
// Бинарник minecraftpe 1.1.5 без символов, поэтому адреса нужно найти
// в Ghidra/IDA и вписать сюда (смещение от базы образа).
// Пример установки хука (нужен ElleKit/Substrate или JIT):
//   uintptr_t base = (uintptr_t)_dyld_get_image_header(0);
//   MSHookFunction((void *)(base + OFFSET_SPRINT), (void *)my_sprint, (void **)&orig_sprint);
//
// Что искать:
//   autosprint  - функция, которая читает флаг "sprinting" у LocalPlayer
//                 (рядом строки/константы про скорость 1.3x). Хук: если gAutoSprint и игрок идёт вперёд, вернуть true.
//   no hurt cam - функция камеры, которая применяет наклон при уроне (hurtTime/hurtDuration).
//                 Хук: если gNoHurtCam, ничего не делать.
//   hitbox show - рендер сущностей: после отрисовки моба/игрока рисовать AABB линиями.

// ====== UI ======
@interface MMPanel : UIView
@property (nonatomic, strong) UIColor *accent;
@end

@implementation MMPanel {
    NSMutableArray<UIView *> *_tinted;
}

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0, 0, 260, 300)];
    _tinted = [NSMutableArray array];
    self.accent = [UIColor systemGreenColor];
    self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.94];
    self.layer.cornerRadius = 14;
    self.layer.borderWidth = 2;
    self.layer.borderColor = self.accent.CGColor;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, 180, 28)];
    title.text = @"Mod Menu";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:18];
    [self addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(self.bounds.size.width - 44, 8, 36, 32);
    [close setTitle:@"✕" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [close addTarget:self action:@selector(hide) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:close];

    [self addRow:@"Auto Sprint" y:52 tag:1];
    [self addRow:@"No Hurt Cam" y:96 tag:2];
    [self addRow:@"Show Hitboxes" y:140 tag:3];

    UILabel *cl = [[UILabel alloc] initWithFrame:CGRectMake(16, 190, 200, 22)];
    cl.text = @"Цвет интерфейса";
    cl.textColor = [UIColor colorWithWhite:0.8 alpha:1];
    cl.font = [UIFont systemFontOfSize:13];
    [self addSubview:cl];

    NSArray *colors = @[UIColor.systemGreenColor, UIColor.systemBlueColor, UIColor.systemPinkColor,
                        UIColor.systemOrangeColor, UIColor.systemPurpleColor];
    for (NSUInteger i = 0; i < colors.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(16 + i * 46, 220, 36, 36);
        b.backgroundColor = colors[i];
        b.layer.cornerRadius = 18;
        b.tag = (NSInteger)i;
        [b addTarget:self action:@selector(pickColor:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:b];
    }
    return self;
}

- (void)addRow:(NSString *)text y:(CGFloat)y tag:(NSInteger)tag {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, y, 160, 32)];
    l.text = text;
    l.textColor = UIColor.whiteColor;
    [self addSubview:l];
    UISwitch *s = [[UISwitch alloc] initWithFrame:CGRectMake(self.bounds.size.width - 66, y, 0, 0)];
    s.tag = tag;
    s.onTintColor = self.accent;
    [s addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:s];
    [_tinted addObject:s];
}

- (void)toggled:(UISwitch *)s {
    switch (s.tag) {
        case 1: gAutoSprint = s.isOn; break;
        case 2: gNoHurtCam  = s.isOn; break;
        case 3: gShowHitbox = s.isOn; break;
    }
}

- (void)pickColor:(UIButton *)b {
    UIColor *c = b.backgroundColor;
    self.accent = c;
    self.layer.borderColor = c.CGColor;
    for (UISwitch *s in _tinted) s.onTintColor = c;
}

- (void)hide { self.hidden = YES; }
@end

static MMPanel *gPanel;

@interface MMGesture : NSObject
+ (void)handle:(UITapGestureRecognizer *)g;
@end
@implementation MMGesture
+ (void)handle:(UITapGestureRecognizer *)g {
    UIView *host = g.view;
    if (!gPanel) {
        gPanel = [[MMPanel alloc] init];
        gPanel.center = CGPointMake(host.bounds.size.width / 2, host.bounds.size.height / 2);
        [host addSubview:gPanel];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [gPanel addGestureRecognizer:pan];
    }
    gPanel.hidden = !gPanel.hidden;
    [host bringSubviewToFront:gPanel];
}
+ (void)drag:(UIPanGestureRecognizer *)p {
    CGPoint t = [p translationInView:p.view.superview];
    p.view.center = CGPointMake(p.view.center.x + t.x, p.view.center.y + t.y);
    [p setTranslation:CGPointZero inView:p.view.superview];
}
@end

static void installGesture(void) {
    UIWindow *w = nil;
    for (UIWindow *c in UIApplication.sharedApplication.windows) { if (c.isKeyWindow) { w = c; break; } }
    if (!w) w = UIApplication.sharedApplication.windows.firstObject;
    if (!w) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ installGesture(); }); return; }
    UITapGestureRecognizer *g = [[UITapGestureRecognizer alloc] initWithTarget:[MMGesture class] action:@selector(handle:)];
    g.numberOfTouchesRequired = 3;
    g.numberOfTapsRequired = 3;
    g.cancelsTouchesInView = NO;
    [w addGestureRecognizer:g];
}

__attribute__((constructor)) static void init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ installGesture(); });
}
