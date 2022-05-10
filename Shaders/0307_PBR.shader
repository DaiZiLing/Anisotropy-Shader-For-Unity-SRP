Shader "Unlit/PBRTest"
{
    Properties
    {
        _BaseColor ("基础颜色", Color) = (1, 1, 1, 1)
        _BaseMap ("基础贴图", 2D) = "white" { }
        [NoScaleOffset]_MaskMap ("MASK贴图", 2D) = "white" { }
        [NoScaleOffset][Normal]_NormalMap ("法线贴图", 2D) = "Bump" { }
        [NoScaleOffset][Normal]_TangentMap ("切线贴图", 2D) = "Bump" { }
        _NormalScale ("法线强度", Range(0.001, 1)) = 1

        [NoScaleOffset]_AnisoAngle ("各向异性角度", 2D) = "white" { } //Tangent的流向
        [NoScaleOffset]_Anisotropy ("各向异性强度", 2D) = "white" { } //Anisotropy,可以是 -1 ~ +1
        _AnisotropyStrength ("各向异性强度百分比", Range(0, 1)) = 1

        _AnisotropyLevel ("各向异性强度系数", Range(0, 20)) = 5 //这个控制各向异性有多细，大于5之后法线为0时，会有噪点
    }

    HLSLINCLUDE

    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
    #include "Assets/PBR/My_PBR.hlsl"

    ENDHLSL

    SubShader
    {
        //定义Tags
        //强迫症狂喜的变量对齐
        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "Opaque" }
        HLSLINCLUDE

        CBUFFER_START(UnityPerMaterial)
        float4   _BaseColor;
        float4   _BaseMap_ST;
        float    _NormalScale;
        float    _AnisotropyStrength;
        float    _AnisotropyLevel;

        TEXTURE2D(_BaseMap);       SAMPLER(sampler_BaseMap);
        TEXTURE2D(_MaskMap);       SAMPLER(sampler_MaskMap);
        TEXTURE2D(_NormalMap);     SAMPLER(sampler_NormalMap);
        TEXTURE2D(_TangentMap);    SAMPLER(sampler_TangentMap);
        TEXTURE2D(_AnisoAngle);    SAMPLER(sampler_AnisoAngle);
        TEXTURE2D(_Anisotropy);    SAMPLER(sampler_Anisotropy);
        CBUFFER_END

        struct a2v
        {
            float4 position:     POSITION;
            float4 normal:       NORMAL;
            float2 texCoord:     TEXCOORD;
            float4 tangent:      TANGENT;
            
        };
        struct v2f
        {
            float4 positionCS:   SV_POSITION;
            float2 texcoord:     TEXCOORD0;
            float3 normalWS:     NORMAL;
            float3 tangentWS:    TANGENT;
            float3 bitangentWS:  TEXCOORD1;
            float3 pos:          TEXCOORD2;
        };
        ENDHLSL

        Pass
        {
            Tags { "LightMode" = "UniversalForward" "RenderType" = "Opaque" }
            HLSLPROGRAM

            #pragma target 4.5
            #pragma vertex VERT
            #pragma fragment FRAG

            v2f VERT(a2v i)
            {
                v2f o;
                //转换一堆参数
                o.positionCS   = TransformObjectToHClip(i.position.xyz);//MVP变换
                o.texcoord.xy  = TRANSFORM_TEX(i.texCoord, _BaseMap);//UV
                o.normalWS     = normalize(TransformObjectToWorldNormal(i.normal.xyz));
                o.tangentWS    = normalize(TransformObjectToWorldDir(i.tangent.xyz));
                o.bitangentWS  = cross(o.normalWS, o.tangentWS);
                o.pos          = TransformObjectToWorld(i.position.xyz);
                return o;
            }
            real4 FRAG(v2f i): SV_TARGET
            {
                //前置数据
                Light mainLight = GetMainLight();

                //贴图处理
                float4 pack_normal    = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.texcoord);
                float3 unpack_normal  = UnpackNormalScale(pack_normal, _NormalScale);

                float4 pack_tangent   = SAMPLE_TEXTURE2D(_TangentMap, sampler_TangentMap, i.texcoord);
                float3 unpack_tangent = UnpackNormalScale(pack_tangent, _NormalScale);

                float3 BaseColor      = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.texcoord.xy).xyz * _BaseColor.xyz; // BaseColor 为 贴图 乘 颜色
                float4 Mask           = SAMPLE_TEXTURE2D(_MaskMap, sampler_MaskMap, i.texcoord.xy); 
                // MASK贴图，R为金属度、G为AO、B为detail normal mask、A为光滑度
                // 采样各向异性Angel的角度，角度为N与T之间的。大面积为灰色，因为它们的夹角是正常的180度。（从N朝上的位置俯视下去）
                
                float Anisotropy  = SAMPLE_TEXTURE2D(_Anisotropy, sampler_Anisotropy, i.texcoord.xy).x ; //这个才是Anisotropy
                float3 AnisoAngle = SAMPLE_TEXTURE2D(_AnisoAngle, sampler_AnisoAngle, i.texcoord.xy).x; //采样各向异性角度
                //Anisotropy =  Anisotropy * 2 - 1; //Anisotropy是T绕着N转的角度。贴图里存的是 0 ~ 1 ，有时需要remap到 -1 ~ + 1
                Anisotropy = Anisotropy * _AnisotropyStrength;
                //float3 huancunAngle = (Anisotropy);
                
                float Metallic   = Mask.r;
                float AO         = Mask.g;
                // mask里的b通道上是Detail Mask，这里用不着就不管了
                float smoothness = Mask.a;

                float3 F0 = lerp(0.04, BaseColor, Metallic);

                float TEMProughness = 1 - smoothness; // 粗糙度的反义词是光滑度
                float roughness     = TEMProughness * 0.5;
                // float roughness = pow(TEMProughness, 2) ;
                // 这里按照迪士尼原则本来得用power 2的，但是由于粗糙度不用整成slider了，所以直接用它本身
                // 但是这里很奇怪，为什么有些时候换URP版本，有些没2次方，有些有2次方呢？好迷！

                // 基础矢量
                float3 position = i.pos;
                float3 T = normalize(i.tangentWS);
                float3 B = normalize(i.bitangentWS);
                float3 N = normalize(unpack_normal.x * _NormalScale * T + unpack_normal.y * _NormalScale * B + unpack_normal.z * i.normalWS);

                // T = normalize(unpack_tangent.x * N * _AnisotropyStrength + unpack_tangent.y * B * _AnisotropyStrength + unpack_tangent.z * i.tangentWS);
                T = normalize(unpack_tangent.x * T + unpack_tangent.y * B * _AnisotropyStrength + unpack_tangent.z * N * _AnisotropyStrength);
                
                float3 L = normalize(mainLight.direction);
                float3 V = normalize(_WorldSpaceCameraPos.xyz - position.xyz);
                float3 H = normalize(V + L);

                // ===============================================================================
                // T = ShiftTangent(N, AnisoAngle);
                // N = ShiftTangent(N, T, AnisoAngle);//各向异性的法线，这里用的是shift tangent。各向异性的结果是 “切线扰动 + 高光变细” 的组合效果，所以还得对GGX动手脚，但是不会！
            
                // 这里是迪士尼原则着色模型的K_aniso和K_aspect，K_aspect处于 0~1 之间
                float K_aniso = Anisotropy;
                float K_aspect = sqrt(1.0f - 0.9f * K_aniso);//DIsney这里是0.9，UE4这里是0.95

                float ax = max(roughness * roughness / K_aspect, 0.001f);
                float ay = max(roughness * roughness * K_aspect, 0.001f);

                // //这是Imageworks的做法：
                // float K_aniso = Anisotropy;
                // float K_aspect = clamp(pow(1 - 0.9 * K_aniso, 0.5), 0, 1);
                // float ax = roughness * roughness / (1 + K_aspect);
                // float ay = roughness * roughness / (1 - K_aspect);

                B = normalize(cross(N, T));

                float3 AnisotropicDir     = (Anisotropy >= 0.0f) ? B : T; //如果Anisotropy大于0，用B、否则用T
                float3 AnisotropicT       = cross(AnisotropicDir, V); 
                float3 AnisotropicN       = cross(AnisotropicT, AnisotropicDir);//UE用的这个，用下面这行会好看一些？
                // float3 AnisotropicN     = cross(T, B);
                float AnisotropicStretch  = abs(Anisotropy) * saturate( _AnisotropyLevel * roughness);
                N = normalize(lerp(N, AnisotropicN, AnisotropicStretch)); 
                // 这种做法叫bent reflection vector，这一块的法线把各向异性产生的粗糙度扰动考虑进去了
                // ===============================================================================

                float3 R = normalize(reflect(-V, N));

                // 基础点乘，对每个数据限制，防止分母为 0
                float NoV = max(saturate(dot(N, V)), 0.000001);
                float NoL = max(saturate(dot(N, L)), 0.000001);
                float HoV = max(saturate(dot(H, V)), 0.000001);
                float NoH = max(saturate(dot(H, N)), 0.000001);
                float LoH = max(saturate(dot(H, L)), 0.000001);

                float ToV = max(saturate(dot(T, V)), 0.000001);
                float ToL = max(saturate(dot(T, L)), 0.000001);
                float BoV = max(saturate(dot(B, V)), 0.000001);
                float BoL = max(saturate(dot(B, L)), 0.000001);
                float ToH = max(saturate(dot(T, H)), 0.000001);
                float BoH = max(saturate(dot(B, H)), 0.000001);
                
                // DGF
                float k   = roughness * pow (2 / PI, 0.5) ;
                float F90 = 0.5 + 2 * roughness * pow(HoV, 2);
                // F90其实也可以暴露出来给美术调
                
                float D   = DistributionGGX(NoH, roughness);
                // float D = D_Beckmann_Aniso(ax, ay, NoH, H, T, B);// 各向异性的D，Beckmann
                // float D = D_GGX_Aniso(ax, ay, NoH, ToH, BoH);// 各向异性的D，GGX
                float G   = GeometrySmith(NoV, NoL, k);
                // float G = G_SmithJointAniso(ax, ay, NoV, NoL, ToV, ToL, BoV, BoL);// 各向异性的G，SmithJointAniso
                float3 F  = FresnelSchlick(LoH, F0, F90);

                // 直接高光项
                float3 specular = D * G * F / (4 * NoV * NoL);

                // 直接漫反射项
                float3 ks          = F; // F已经帮我们把Ks实现了，金属的 f0
                float3 kd          = (1 - ks) * (1 - Metallic);// kd漫反射的那部分，所以它的金属度是1 - Metallic，它是电介质的漫反射
                float3 diffuse     = kd * BaseColor / PI;//Lambert Diffuse

                float3 DirectColor = (diffuse + specular) * NoL * PI * mainLight.color;

                // 间接光漫反射
                float3 SH = SH_Process(N) * AO * AO;
                // 球谐与AO做一个正片叠底
                
                float3 IndirKS        = IndirFresnelSchlick(NoV, F0, roughness);
                // 为什么这里是NoV，而函数里是HoV？NoV是宏观的，不基于微表面那一套，使用宏观即可；HoV是已经筛选过的高光法线。
                // 不能用直接光那一套微表面的m=h。
                float3 IndirKD        = (1 - IndirKS) * (1 - Metallic);
                // 间接光的菲涅尔
                float3 IndirDiffColor = SH * IndirKD * BaseColor; //间接光的漫反射

                // 间接光高光
                roughness                     =  roughness * (1.7 - 0.7 * roughness);
                float mip_level               = (roughness * (1.7 - 0.7 * roughness)) * 6.0;
                float3 IndirSpecularBaseColor = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, R, mip_level) * AO ;

                float surfaceReduction        = 1.0 / (roughness * roughness + 1.0);
                // surfaceReduction是进一步对IBL的修正。
                float ReflectivitySpecular;

                // ReflectivitySpecular = max(max(specular.r, specular.g), specular.b);
                
                #if defined(SHADER_API_GLES)//移动端阉割
                    ReflectivitySpecular = specular.r; // Red channel - because most metals are either monocrhome or with redish/yellowish tint
                    // 大多数金属要么是单色的（比如铁、锌；要么是红色或者黄色的调子，比如铜、金）
                #else
                    ReflectivitySpecular = max(max(specular.r, specular.g), specular.b); 
                    // 移动端直接用R，其他端把RGB取个最大值。
                #endif
                
                half grazingTerm   = saturate((1 - roughness) + (1 - (1 - ReflectivitySpecular)));
                // grazingTerm是用来添加更真实的菲涅尔反射
                half t             = pow(1 - NoV, 5);
                float3 FresnelLerp = lerp(F0, grazingTerm, t);

                float3 IndirSpecularResult = IndirSpecularBaseColor * FresnelLerp * surfaceReduction; //间接光的高光

                float3 IndirColor          = IndirSpecularResult + IndirDiffColor;

                return half4(DirectColor + IndirColor, 1.0);
            }

            ENDHLSL

        }

        Pass // 阴影Pass
        {
            Name "ShadowCaster"
            Tags{"LightMode" = "ShadowCaster"}

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull off

            HLSLPROGRAM
            #pragma exclude_renderers gles gles3 glcore
            #pragma target 4.5

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON

            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }
    }
}
