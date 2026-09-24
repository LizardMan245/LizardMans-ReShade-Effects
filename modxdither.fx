#include "ReShade.fxh"

uniform int Direction <
    ui_type  = "combo";
    ui_items = "Along X (vertical stripes)\0Along Y (horizontal stripes)\0";
    ui_label = "Stripe direction";
> = 0;

uniform int Levels <
    ui_type = "slider"; ui_min = 2; ui_max = 16;
    ui_label = "Number of shades";
> = 4;

uniform int StripeWidth <
    ui_type = "slider"; ui_min = 2; ui_max = 16;
    ui_label = "Stripe width";
> = 4;

uniform float Strength <
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0;
    ui_label = "Dither strength";
> = 1.0;

float3 DitherPass(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    // 1. Read the game color and turn it into brightness
    float3 color = tex2D(ReShade::BackBuffer, uv).rgb;
    float brightness = dot(color, float3(0.2126, 0.7152, 0.0722));

    // 2. Make the stripe nudge (X or Y)
    float where = (Direction == 0) ? pos.x : pos.y;
    float nudge = frac(floor(where) / StripeWidth);
    nudge = lerp(0.5, nudge, Strength);   // Strength 0 = no dither, just flat bands

    // 3. Add the nudge, then snap to a few shades
    float steps = Levels - 1;
    float snapped = floor(brightness * steps + nudge) / steps;

    return float3(snapped, snapped, snapped);
}

technique ModXDither
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = DitherPass;
    }
}