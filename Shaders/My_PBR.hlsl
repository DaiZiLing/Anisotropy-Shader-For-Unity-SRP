
            //DGF
            // use GGX / Trowbridge-Reitz, same as Disney and Unreal 4
            // cf http://blog.selfshadow.com/publications/s2013-shading-course/karis/s2013_pbs_epic_notes_v2.pdf p3
            float DistributionGGX(float NoH, float roughness)//先是D，这是GGX NDF
            {
                float a2 = roughness * roughness;
                float NoH2 = NoH * NoH;

                float nom = a2;
                float denom = NoH2 * (a2 - 1.0) + 1.0;
                denom = denom * denom * PI;

                return nom / denom;
            }

            float GeometrySchlickGGX1(float NoV, float k)//再是G，下面这三个合起来是Smith-Schlick G
            {
                float nom = NoV;
                float denom = NoV * (1.0 - k) + k;
                return nom / denom;
            }

            float GeometrySchlickGGX2(float NoL, float k)
            {
                float nom = NoL;
                float denom = NoL * (1.0 - k) + k;
                return nom / denom;
            }

            float GeometrySmith(float NoV, float NoL, float k)
            {
                float ggx1 = GeometrySchlickGGX1(NoV, k);
                float ggx2 = GeometrySchlickGGX2(NoL, k);
                return (ggx1 * ggx2);
            }

            float3 FresnelSchlick(float HoV, float3 F0, float3 F90)//再是F，这个就很简单了，Fresnel-Schlick直接套。一个直接光一个间接光
            {
                return F0 + (F90 - F0) * pow(1.0 - HoV, 5.0);
                //此处指数计算在UE4里用球面高斯优化了
                //pow(1.0 - Hov, 5.0) = exp2(-8.35 * Hov)
            }

            float3 IndirFresnelSchlick(float HoV, float3 F0, float roughness)
            {
                return F0 + (max(float3(1, 1, 1) * (1 - roughness), F0) - F0) * pow(1.0 - HoV, 5.0);
            }

            float3 ShiftTangent(float N, float T ,float AnisoAngle)//这个是shift tangent的做法
            {
                float3 shiftedT = T + AnisoAngle * N;
                return normalize(shiftedT);
            }

            float3 RotateTangent(float T, float3 B, float AnisoAngle)//这个是Rotate tangent的做法，本shader中选择这么做
            {
                float3 RotateT = B + AnisoAngle * T;
                return normalize(RotateT);
            }

            //各向异性部分
            float D_Beckmann_Aniso(float ax, float ay, float NoH, float3 H, float3 T, float3 B) //直接抄UE4的BRDF.ush
            {
                float ToH = max(saturate(dot(T, H)), 0.000001);
                float BoH = max(saturate(dot(B, H)), 0.000001);
                float nom = - (ToH * ToH / (ax * ax) + BoH * BoH /(ay * ay)) / (NoH * NoH);
                float denom = PI * ax * ay * NoH * NoH * NoH * NoH ;
                return exp(nom) / denom;
            }

            float D_GGX_Aniso(float ax, float ay, float NoH, float ToH, float BoH) //这个是GGX Aniso
            {
                float d = ToH * ToH / (ax * ax) + BoH * BoH / (ay * ay) + (NoH * NoH);
                float denom = PI * ax * ay * d * d;
                return 1.0f / denom;
            }

            float G_SmithJointAniso(float ax, float ay, float NoV, float NoL, float ToV, float ToL, float BoV, float BoL)
            //这个是ue4的Vis_SmithJointAniso
            {
                float Vis_SmithV = NoL * length(float3(ax * ToV, ay * BoV, NoV));
                float Vis_SmithL = NoV * length(float3(ax * ToL, ay * BoL, NoL));
                return 0.5 * rcp(Vis_SmithV + Vis_SmithL);
            }
            //各向异性部分

            float3 SH_Process(float3 N)//获得环境光球谐
            {
                float4 SH[7];
                SH[0] = unity_SHAr;
                SH[1] = unity_SHAg;
                SH[2] = unity_SHAb;
                SH[3] = unity_SHBr;
                SH[4] = unity_SHBr;
                SH[5] = unity_SHBr;
                SH[6] = unity_SHC;

                return max(0.0, SampleSH9(SH, N));
            }
