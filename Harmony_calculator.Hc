 // Harmony Calculator in TempleOS (HolyC)

// Constants
#define NUM_NOTES 12
#define BASE_FREQ 261.63  // C4

// Note names
U8 *noteNames[NUM_NOTES] = {
  "C", "C#", "D", "D#", "E", "F",
  "F#", "G", "G#", "A", "A#", "B"
};

// Frequency multiplier for semitones
F64 SemitoneRatio = Pow(2.0, 1.0/12.0);

// Get frequency of a note relative to base C
F64 NoteFreq(I64 noteIdx) {
  return BASE_FREQ * Pow(SemitoneRatio, noteIdx);
}

// Draw the note and highlight triad
Void DrawKeyboard(I64 root) {
  I64 i;
  I64 w = 40, h = 60;
  I64 x = 100, y = 100;

  ClrScr();

  for (i = 0; i < NUM_NOTES; ++i) {
    I64 dx = x + i * w;
    Bool isRoot = i == root;
    Bool isThird = i == (root + 4) % 12;
    Bool isFifth = i == (root + 7) % 12;

    U32 color = isRoot ? RED :
                isThird ? GREEN :
                isFifth ? BLUE :
                LTGRAY;

    // Draw rectangle
    DrawRect(dx, y, dx+w-2, y+h-2, color);

    // Draw note name
    TextAttr = BLACK;
    PrintAt(dx+10, y+h/2-8, noteNames[i]);
  }

  TextAttr = YELLOW;
  PrintAt(100, 50, "Use LEFT/RIGHT arrows to change root note.");
  PrintAt(100, 70, "Red = Root, Green = Major Third, Blue = Perfect Fifth");
}

// Play note using basic square wave synth
Void PlayNote(F64 freq, I64 durationMs) {
  I64 i, samples = durationMs * 44;
  F64 t, dt = 1.0 / 44100.0;

  for (i = 0; i < samples; ++i) {
    t = i * dt;
    F64 val = Sin(2*PI*freq*t);
    U8 amp = (val > 0) ? 200 : 56;
    Sound(amp, amp);
  }
}

// Play chord
Void PlayChord(I64 root) {
  I64 i;
  F64 freqs[3];
  freqs[0] = NoteFreq(root);
  freqs[1] = NoteFreq((root + 4) % 12);
  freqs[2] = NoteFreq((root + 7) % 12);

  I64 j, duration = 400;
  for (j = 0; j < duration * 44; ++j) {
    F64 t = j / 44100.0;
    F64 mix = 0;
    for (i = 0; i < 3; ++i)
      mix += Sin(2 * PI * freqs[i] * t);

    U8 amp = 128 + 80 * mix / 3;
    Sound(amp, amp);
  }
}

// Main UI loop
Void HarmonyCalculator() {
  I64 root = 0;
  DrawKeyboard(root);
  PlayChord(root);

  While (1) {
    U8 key = GetKey();
    If (key == SC_LEFT) {
      root = (root + NUM_NOTES - 1) % NUM_NOTES;
      DrawKeyboard(root);
      PlayChord(root);
    } ElseIf (key == SC_RIGHT) {
      root = (root + 1) % NUM_NOTES;
      DrawKeyboard(root);
      PlayChord(root);
    } ElseIf (key == SC_ESC)
      Break;
  }
}
