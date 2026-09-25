#include "ReShade.fxh"

// SuperModDither: a 1-bit modulation dither.
// A fine line carrier is phase-shifted by (smoothed) brightness, so lines bend
// along the image's contours, and each line gets thicker as the image gets brighter.

uniform float CarrierAngle <
    ui_type = "slider"; ui_min = 0.0; ui_max = 180.0; ui_step = 1.0;
    ui_category = "Carrier";
    ui_label = "Line angle";
    ui_tooltip = "0 = vertical lines, 90 = horizontal lines.";
> = 90.0;

uniform float CarrierPeriod <
    ui_type = "slider"; ui_min = 2.0; ui_max = 32.0; ui_step = 0.1;
    ui_category = "Carrier";
    ui_label = "Line spacing";
> = 3.5;

uniform float ModDepth <
    ui_type = "slider"; ui_min = 0.0; ui_max = 32.0; ui_step = 0.1;
    ui_category = "Carrier";
    ui_label = "Modulation depth";
    ui_tooltip = "How far brightness bends the lines. Higher = lines follow image contours more (topographic look).";
> = 6.0;

uniform float Smoothing <
    ui_type = "slider"; ui_min = 0.0; ui_max = 12.0; ui_step = 0.1;
    ui_category = "Carrier";
    ui_label = "Contour smoothing";
    ui_tooltip = "Blur applied to the brightness that bends the lines. Higher = calmer, wavier lines.";
> = 3.0;

uniform float DriftSpeed <
    ui_type = "slider"; ui_min = -4.0; ui_max = 4.0; ui_step = 0.01;
    ui_category = "Carrier";
    ui_label = "Line drift speed";
    ui_tooltip = "Scrolls the lines over time. 0 = still.";
> = 0.0;

uniform float Grain <
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0;
    ui_category = "Grain";
    ui_label = "Grain amount";
    ui_tooltip = "Random speckle that breaks lines into dots in the shadows.";
> = 0.35;

uniform bool AnimateGrain <
    ui_category = "Grain";
    ui_label = "Animate grain";
> = false;

uniform float BlackPoint <
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0;
    ui_category = "Tone";
    ui_label = "Black point";
> = 0.0;

uniform float WhitePoint <
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0;
    ui_category = "Tone";
    ui_label = "White point";
> = 1.0;

uniform float Gamma <
    ui_type = "slider"; ui_min = 0.2; ui_max = 4.0;
    ui_category = "Tone";
    ui_label = "Gamma";
    ui_tooltip = "Higher = darker, sparser lines in the midtones.";
> = 1.3;

uniform int PixelSize <
    ui_type = "slider"; ui_min = 1; ui_max = 8;
    ui_category = "Output";
    ui_label = "Pixel size";
> = 1;

uniform int ColorMode <
    ui_type  = "combo";
    ui_items = "Two-tone (ink / paper)\0Source color\0";
    ui_category = "Output";
    ui_label = "Color mode";
> = 0;

uniform float3 InkColor <
    ui_type = "color";
    ui_category = "Output";
    ui_label = "Ink color";
> = float3(0.04, 0.69, 0.23);

uniform float3 PaperColor <
    ui_type = "color";
    ui_category = "Output";
    ui_label = "Paper color";
> = float3(0.0, 0.0, 0.0);

uniform float Strength <
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0;
    ui_category = "Output";
    ui_label = "Effect strength";
> = 1.0;

uniform float Timer < source = "timer"; >;
uniform int FrameCount < source = "framecount"; >;

texture SMD_LumaTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
texture SMD_BlurTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R16F; };
sampler SMD_LumaSampler { Texture = SMD_LumaTex; };
sampler SMD_BlurSampler { Texture = SMD_BlurTex; };

static const int BLUR_TAPS = 6; // taps on each side of the center

float Tone(float3 color)
{
    float l = dot(color, float3(0.2126, 0.7152, 0.0722));
    l = saturate((l - BlackPoint) / max(WhitePoint - BlackPoint, 1e-4));
    return pow(l, Gamma);
}

float Hash(float2 p)
{
    float3 p3 = frac(p.xyx * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

// Separable gaussian over +-2 sigma, sigma = Smoothing pixels (scaled by PixelSize)
float BlurWeight(int i)
{
    float x = i / (BLUR_TAPS * 0.5);
    return exp(-0.5 * x * x);
}

float BlurHPass(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float2 stepUV = float2(Smoothing * PixelSize * 2.0 / BLUR_TAPS, 0.0) * ReShade::PixelSize;
    float sum = 0.0, wsum = 0.0;
    for (int i = -BLUR_TAPS; i <= BLUR_TAPS; i++)
    {
        float w = BlurWeight(i);
        sum  += Tone(tex2D(ReShade::BackBuffer, uv + stepUV * i).rgb) * w;
        wsum += w;
    }
    return sum / wsum;
}

float BlurVPass(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float2 stepUV = float2(0.0, Smoothing * PixelSize * 2.0 / BLUR_TAPS) * ReShade::PixelSize;
    float sum = 0.0, wsum = 0.0;
    for (int i = -BLUR_TAPS; i <= BLUR_TAPS; i++)
    {
        float w = BlurWeight(i);
        sum  += tex2D(SMD_LumaSampler, uv + stepUV * i).r * w;
        wsum += w;
    }
    return sum / wsum;
}

float3 DitherPass(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float3 original = tex2D(ReShade::BackBuffer, uv).rgb;

    // 1. Snap to the pixel grid and read the cell's color and brightness
    float2 cell   = floor(pos.xy / PixelSize);
    float2 cellUV = (cell + 0.5) * PixelSize * ReShade::PixelSize;
    float3 color  = tex2D(ReShade::BackBuffer, cellUV).rgb;
    float  lum    = Tone(color);
    float  smoothLum = tex2D(SMD_BlurSampler, cellUV).r;

    // 2. Carrier phase: position along the line direction, bent by smoothed brightness
    float2 dir;
    sincos(radians(CarrierAngle), dir.y, dir.x);
    float phase = dot(cell, dir) / CarrierPeriod + smoothLum * ModDepth + Timer * 0.001 * DriftSpeed;

    // 3. Triangle wave (0 at line center, 1 between lines); ink where it's under brightness,
    //    so line thickness follows brightness. Grain fades out in pure black.
    float wave  = abs(frac(phase) * 2.0 - 1.0);
    float seed  = AnimateGrain ? float(FrameCount % 1024) : 0.0;
    float noise = Hash(cell + seed * float2(17.0, 31.0)) - 0.5;
    float ink   = (wave < lum + noise * Grain * saturate(lum * 16.0)) ? 1.0 : 0.0;

    // 4. Color it
    float3 inkColor = (ColorMode == 0) ? InkColor : color;
    float3 result   = lerp(PaperColor, inkColor, ink);

    return lerp(original, result, Strength);
}

technique SuperModDither
{
    pass BlurH
    {
        VertexShader = PostProcessVS;
        PixelShader  = BlurHPass;
        RenderTarget = SMD_LumaTex;
    }
    pass BlurV
    {
        VertexShader = PostProcessVS;
        PixelShader  = BlurVPass;
        RenderTarget = SMD_BlurTex;
    }
    pass Dither
    {
        VertexShader = PostProcessVS;
        PixelShader  = DitherPass;
    }
}
