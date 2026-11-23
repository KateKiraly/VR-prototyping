// Sci-fi hologram: additive, fresnel edges, moving scanlines, flicker and glitch jumps.
Shader "ShaderPack/FX/Hologram"
{
    Properties
    {
        [HDR] _HoloColor ("Hologram Color", Color) = (0.2, 0.9, 1, 1)
        _BaseMap ("Texture", 2D) = "white" {}
        _Alpha ("Base Opacity", Range(0, 1)) = 0.3
        _FresnelPower ("Fresnel Power", Range(0.1, 8)) = 2

        [Header(Scanlines)]
        _ScanlineDensity ("Scanline Density", Float) = 30
        _ScanlineSpeed ("Scanline Speed", Float) = 2
        _ScanlineStrength ("Scanline Strength", Range(0, 1)) = 0.5
        _BandStrength ("Sweep Band Strength", Range(0, 2)) = 0.6

        [Header(Glitch)]
        _FlickerSpeed ("Flicker Speed", Float) = 20
        _FlickerStrength ("Flicker Strength", Range(0, 1)) = 0.15
        _GlitchAmount ("Glitch Offset", Range(0, 0.5)) = 0.05
        _GlitchFrequency ("Glitch Frequency", Range(0, 20)) = 3
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" "IgnoreProjector"="True" }

        Pass
        {
            Name "HologramForward"
            Tags { "LightMode"="UniversalForward" }
            Blend SrcAlpha One
            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4  _HoloColor;
                half   _Alpha;
                half   _FresnelPower;
                float  _ScanlineDensity;
                float  _ScanlineSpeed;
                half   _ScanlineStrength;
                half   _BandStrength;
                float  _FlickerSpeed;
                half   _FlickerStrength;
                float  _GlitchAmount;
                float  _GlitchFrequency;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct Varyings   { float4 positionHCS : SV_POSITION; float2 uv : TEXCOORD0; float3 normalWS : TEXCOORD1; float3 positionWS : TEXCOORD2; };

            float Hash1 (float x) { return frac(sin(x * 12.9898) * 43758.5453); }

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                float3 posWS = TransformObjectToWorld(IN.positionOS.xyz);

                // Occasional horizontal glitch: random slices jump sideways for a moment
                float tStep = floor(_Time.y * _GlitchFrequency);
                float on    = step(0.85, Hash1(tStep));
                float slice = step(0.7, Hash1(floor(posWS.y * 10.0) + tStep));
                posWS.x += on * slice * (Hash1(tStep + 3.1) - 0.5) * 2.0 * _GlitchAmount;

                OUT.positionWS  = posWS;
                OUT.positionHCS = TransformWorldToHClip(posWS);
                OUT.normalWS    = TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv          = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                float3 N = normalize(IN.normalWS);
                float3 V = normalize(GetWorldSpaceViewDir(IN.positionWS));
                half fres = pow(1.0 - saturate(dot(N, V)), _FresnelPower);

                float scan     = frac(IN.positionWS.y * _ScanlineDensity - _Time.y * _ScanlineSpeed);
                half  scanLine = lerp(1.0, step(0.5, scan), _ScanlineStrength);
                half  band     = pow(frac(IN.positionWS.y * 0.3 - _Time.y * 0.5), 20.0) * _BandStrength;
                half  flicker  = 1.0 - _FlickerStrength * Hash1(floor(_Time.y * _FlickerSpeed));

                half4 tex   = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                half3 col   = tex.rgb * _HoloColor.rgb * (1.0 + fres);
                half  alpha = saturate((_Alpha + fres) * scanLine + band) * flicker * tex.a * _HoloColor.a;
                return half4(col, alpha);
            }
            ENDHLSL
        }
    }
}
