 #define N 256
F64 cosLUT[N/2], sinLUT[N/2];
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
    U8 val = InU8(0x22A);
    if (val != 0xAA)
        "DSP reset failed\n";
}

U0 DSP_StartCapture(U16 sampleRate) {
    U8 timeConst = 256 - (1000000 / sampleRate);
    DSP_Write(0x40);
    DSP_Write(timeConst);
    DSP_Write(0x20); // 8-bit mono
    DSP_Write(0xFF); // LSB
    DSP_Write(0x00); // MSB
}

U0 DSP_CaptureFrame() {
    I64 i = 0;
    while (i < N) {
        if (InU8(0x22E) & 0x80) {
            audioBuf[i++] = InU8(0x22A);
        }
    }
}

U0 InitLUT() {
    I64 i;
    for (i = 0; i < N/2; ++i) {
        cosLUT[i] = Cos(2*PI*i/N);
        sinLUT[i] = -Sin(2*PI*i/N);
    }
}

I64 BitReverse(I64 x, I64 bits) {
    I64 i, r=0;
    for (i=0; i<bits; ++i)
        r = (r<<1) | (x&1), x>>=1;
    return r;
}

U0 Swap(F64 *a, F64 *b) {
    F64 tmp=*a;
    *a=*b; *b=tmp;
}

U0 FFT(F64 real[N], F64 imag[N]) {
    I64 i,j,k,m,step,half;
    for (i=0;i<N;++i) {
        j=BitReverse(i,8);
        if (j>i) {Swap(&real[i],&real[j]); Swap(&imag[i],&imag[j]);}
    }
    for (half=1;half<N;half*=2) {
        step=half*2;
        for (i=0;i<N;i+=step) {
            for (j=0;j<half;++j) {
                k=j*N/step;
                F64 t_re=cosLUT[k]*real[i+j+half]-sinLUT[k]*imag[i+j+half];
                F64 t_im=cosLUT[k]*imag[i+j+half]+sinLUT[k]*real[i+j+half];
                F64 u_re=real[i+j], u_im=imag[i+j];
                real[i+j]=u_re+t_re;
                imag[i+j]=u_im+t_im;
                real[i+j+half]=u_re-t_re;
                imag[i+j+half]=u_im-t_im;
            }
        }
    }
}

U0 DrawUI() {
    // Scale and gain sliders
    I64 mx=MouseX, my=MouseY;
    gain = 0.5 + mx / 640.0 * 3.5;
    scale = 5 + (480-my) / 60.0;

    Rect(10, 10, 220, 30, DARK_GREY);
    "Gain: %.2f" gain;
    Rect(10, 40, 220, 60, DARK_GREY);
    "Scale: %.2f" scale;
}

U0 DrawSpectrum(F64 real[N], F64 imag[N]) {
    Cls();
    DrawUI();
    I64 i;
    for (i=0;i<N/2;++i) {
        F64 mag = gain*Sqrt(real[i]*real[i] + imag[i]*imag[i]) / N;
        I64 h = min(200, mag*scale);
        Line(i*2, 300, i*2, 300 - h, WHITE);
    }
}

U0 Main() {
    I64 i;
    Cls();
    DSP_Reset();
    InitLUT();
    DSP_StartCapture(8000); // 8 kHz sample rate

    for (;;) {
        DSP_CaptureFrame();
        for (i=0;i<N;++i) {
            real[i] = (F64)(audioBuf[i] - 128);
            imag[i] = 0;
        }
        FFT(real, imag);
        DrawSpectrum(real, imag);
        Sleep(0.02);
    }
}
