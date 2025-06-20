#define N 256
#define N2 (N/2)
F64 cosLUT[N2], sinLUT[N2];
U8 audioBuf[N];
F64 real[N], imag[N], prevMag[N2], mag[N2];
F64 gain=1.0, scale=10.0, smooth=0.2;

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

U0 VectorizeAudio(F64 *dst) {
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
            for (j=0; j<half; j+=2) {
                k = j*N/step;
                F64 cr0 = cosLUT[k], sr0 = sinLUT[k];
                F64 cr1 = cosLUT[k+1], sr1 = sinLUT[k+1];

                F64 tr0 = cr0*re[i+j+half] - sr0*im[i+j+half];
                F64 ti0 = cr0*im[i+j+half] + sr0*re[i+j+half];
                F64 ur0 = re[i+j], ui0 = im[i+j];
                re[i+j] = ur0 + tr0; im[i+j] = ui0 + ti0;
                re[i+j+half] = ur0 - tr0; im[i+j+half] = ui0 - ti0;

                F64 tr1 = cr1*re[i+j+1+half] - sr1*im[i+j+1+half];
                F64 ti1 = cr1*im[i+j+1+half] + sr1*re[i+j+1+half];
                F64 ur1 = re[i+j+1], ui1 = im[i+j+1];
                re[i+j+1] = ur1 + tr1; im[i+j+1] = ui1 + ti1;
                re[i+j+1+half] = ur1 - tr1; im[i+j+1+half] = ui1 - ti1;
            }
        }
    }
}

U0 VectorMagnitude(F64 *re, F64 *im, F64 *out) {
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
    smooth = 0.05 + (480 - MouseY) / 600.0;
    Rect(10, 10, 220, 30, DARK_GREY);
    "Gain: %.2f" gain;
    Rect(10, 40, 220, 60, DARK_GREY);
    "Smooth: %.2f" smooth;
}

U0 DrawSpectrum(F64 *mag) {
    Cls();
    DrawUI();
    I64 i;
    for (i=1; i<N2; ++i) {
        F64 logx = Log(i+1)/Log(N2);
        I64 x = logx * 640;
        F64 h = gain * mag[i] * scale;
        I64 y = min(200, h);
        Line(x, 400, x, 400 - y, WHITE);
    }
}

U0 SmoothSpectrum(F64 *src, F64 *prev, F64 *dst, F64 alpha) {
    I64 i;
    for (i=0; i<N2; ++i)
        dst[i] = alpha*src[i] + (1-alpha)*prev[i];
}

U0 Main() {
    Cls();
    DSP_Reset();
    InitLUT();
    DSP_StartCapture(8000);
    MemSet(prevMag, 0, sizeof(prevMag));

    for (;;) {
        DSP_CaptureFrame();
        VectorizeAudio(real);
        MemSet(imag, 0, sizeof(imag));
        FFT_SSE2(real, imag);
        VectorMagnitude(real, imag, mag);
        SmoothSpectrum(mag, prevMag, mag, smooth);
        MemCpy(prevMag, mag, sizeof(mag));
        DrawSpectrum(mag);
        Sleep(0.005);
    }
}
