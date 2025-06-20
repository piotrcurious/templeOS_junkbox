#define N 256
#define N2 (N/2)
F64 cosLUT[N2], sinLUT[N2];
U8 audioBuf[N];
F64 real[N], imag[N];
F64 gain=1.0, scale=10.0;

U8 DSP_Read() {
    while (!(InU8(0x22E) & 0x80)) {}
    return InU8(0x22A);
}

U0 DSP_Write(U8 val) {
    while (InU8(0x22C) & 0x80) {}
    OutU8(0x22C, val);
}

U0 DSP_Reset() {
    OutU8(0x226, 1);
    Sleep(0.01);
    OutU8(0x226, 0);
    while (!(InU8(0x22E) & 0x80)) {}
    if (InU8(0x22A) != 0xAA)
        "SB DSP not found.\n";
}

U0 DSP_StartCapture(U16 sampleRate) {
    U8 timeConst = 256 - (1000000 / sampleRate);
    DSP_Write(0x40);
    DSP_Write(timeConst);
    DSP_Write(0x20); // mono, 8-bit
    DSP_Write(0xFF);
    DSP_Write(0x00);
}

U0 DSP_CaptureFrame() {
    I64 i = 0;
    while (i < N) {
        if (InU8(0x22E) & 0x80)
            audioBuf[i++] = InU8(0x22A);
    }
}

U0 InitLUT() {
    I64 i;
    for (i = 0; i < N2; ++i) {
        cosLUT[i] = Cos(2*PI*i/N);
        sinLUT[i] = -Sin(2*PI*i/N);
    }
}

U0 FFT_SSE2(F64 *re, F64 *im) {
    I64 i,j,k,m,step,half;

    for (i=0;i<N;++i) {
        j = BitReverse(i,8);
        if (j>i) {
            F64 tmp = re[i]; re[i]=re[j]; re[j]=tmp;
            tmp = im[i]; im[i]=im[j]; im[j]=tmp;
        }
    }

    for (half=1; half<N; half*=2) {
        step = half*2;
        for (i=0; i<N; i+=step) {
            for (j=0; j<half; ++j) {
                k = j*N/step;
                F64 cr = cosLUT[k], sr = sinLUT[k];
                F64 tr = cr*re[i+j+half] - sr*im[i+j+half];
                F64 ti = cr*im[i+j+half] + sr*re[i+j+half];

                F64 ur = re[i+j], ui = im[i+j];
                re[i+j] = ur + tr;
                im[i+j] = ui + ti;
                re[i+j+half] = ur - tr;
                im[i+j+half] = ui - ti;
            }
        }
    }
}

U0 VectorizeAudio(F64 *dst) {
    // Convert 8-bit audio to F64 centered on 0 using SSE2
    I64 i;
    for (i = 0; i < N; i += 2) {
        I64 a = audioBuf[i] - 128;
        I64 b = audioBuf[i+1] - 128;
        ASM {
            mov rax,a
            cvtsi2sd xmm0,rax
            mov rax,b
            cvtsi2sd xmm1,rax
            movsd qword ptr dst[i],xmm0
            movsd qword ptr dst[i+1],xmm1
        }
    }
}

U0 VectorMagnitude(F64 *re, F64 *im, F64 *out) {
    // out[i] = sqrt(re[i]^2 + im[i]^2)
    I64 i;
    for (i = 0; i < N2; i += 2) {
        ASM {
            movapd xmm0, oword ptr re[i]
            movapd xmm1, oword ptr im[i]
            mulpd  xmm0, xmm0
            mulpd  xmm1, xmm1
            addpd  xmm0, xmm1
            sqrtpd xmm0, xmm0
            movapd oword ptr out[i], xmm0
        }
    }
}

U0 DrawUI() {
    gain = 0.5 + MouseX / 640.0 * 3.5;
    scale = 5 + (480 - MouseY) / 60.0;
    Rect(10, 10, 220, 30, DARK_GREY);
    "Gain: %.2f" gain;
    Rect(10, 40, 220, 60, DARK_GREY);
    "Scale: %.2f" scale;
}

U0 DrawSpectrum(F64 *mag) {
    Cls();
    DrawUI();
    I64 i;
    for (i=0; i<N2; ++i) {
        F64 h = gain * mag[i] * scale;
        I64 y = min(200, h);
        Line(i*2, 300, i*2, 300 - y, WHITE);
    }
}

U0 Main() {
    Cls();
    DSP_Reset();
    InitLUT();
    DSP_StartCapture(8000);

    F64 mag[N];
    for (;;) {
        DSP_CaptureFrame();
        VectorizeAudio(real);
        MemSet(imag, 0, sizeof(imag));
        FFT_SSE2(real, imag);
        VectorMagnitude(real, imag, mag);
        DrawSpectrum(mag);
        Sleep(0.01);
    }
}
