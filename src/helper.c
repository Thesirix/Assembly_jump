// =============================================================
// helper.c — Pont C exposé à l'assembleur NASM x86-64
// Pattern identique au bridge ASM <-> Objective-C du projet CX
// (Mandelbrot AArch64 + ObjC), ici adapté pour Windows x64.
//
// Compilation : cl.exe /c /O2 /nologo helper.c /Fohelper.obj
// Liaison     : link ... helper.obj ...
//
// Convention Win64 ABI :
//   Arguments flottants : xmm0, xmm1, xmm2, xmm3
//   Arguments entiers   : rcx, rdx, r8, r9
//   Retour flottant     : xmm0
//   Retour entier       : rax
// =============================================================

#include <math.h>

// =============================================================
// helper_perlin2d — Bruit de Perlin 2D double précision
// Entrée : xmm0 = x (double), xmm1 = y (double)
// Retour : xmm0 (double) dans [-1.0, +1.0]
//
// Utilise une fonction de hash déterministe et l'interpolation
// bicubique (smooth step fade : 6t^5 - 15t^4 + 10t^3)
// =============================================================
__declspec(dllexport) double helper_perlin2d(double x, double y)
{
    // Coordonnées de la cellule entière (modulo 256)
    int xi = (int)floor(x) & 255;
    int yi = (int)floor(y) & 255;

    // Partie fractionnaire dans la cellule
    double xf = x - floor(x);
    double yf = y - floor(y);

    // Fade function (cubic hermite / smoothstep de Perlin)
    // u = 6t^5 - 15t^4 + 10t^3
    double u = xf * xf * xf * (xf * (xf * 6.0 - 15.0) + 10.0);
    double v = yf * yf * yf * (yf * (yf * 6.0 - 15.0) + 10.0);

    // Hash déterministe pour les 4 coins de la cellule
    // Utilise des constantes multiplicatives de hash (Jenkins-style)
    int h00 = ((xi * 1619 + yi * 31337 + 1013904223) * 1664525) & 0x7FFFFFFF;
    int h10 = (((xi + 1) * 1619 + yi * 31337 + 1013904223) * 1664525) & 0x7FFFFFFF;
    int h01 = ((xi * 1619 + (yi + 1) * 31337 + 1013904223) * 1664525) & 0x7FFFFFFF;
    int h11 = (((xi + 1) * 1619 + (yi + 1) * 31337 + 1013904223) * 1664525) & 0x7FFFFFFF;

    // Gradient pseudo-aléatoire dans [-1.0, +1.0]
    double g00 = (h00 / 1073741824.0) - 1.0;
    double g10 = (h10 / 1073741824.0) - 1.0;
    double g01 = (h01 / 1073741824.0) - 1.0;
    double g11 = (h11 / 1073741824.0) - 1.0;

    // Interpolation bilinéaire avec fade
    double ix0 = g00 + u * (g10 - g00); // interpoler sur x, y=0
    double ix1 = g01 + u * (g11 - g01); // interpoler sur x, y=1
    return ix0 + v * (ix1 - ix0);       // interpoler sur y
}

// =============================================================
// helper_smooth_log — Smooth coloring style Mandelbrot
// Entrée : xmm0 = valeur double (ex: abs(camera_y))
// Retour : xmm0 (double) dans [0.0, 255.0]
//
// Formule : log(log(val + 2.0)) / log(2) * 80
// Identique au smooth coloring du renderer Mandelbrot CX
// qui utilise log(log(|z|^2)) / log(2) pour les iso-bandes.
// =============================================================
__declspec(dllexport) double helper_smooth_log(double val)
{
    if (val <= 0.0)
        return 0.0;

    // Smooth coloring logarithmique calibré pour les altitudes du jeu (0..~15000 px)
    // Formule : log(val/1800 + 1) * 110
    //   val=0     → 0.0   (ciel bleu pur au départ)
    //   val=3000  → 108   (mi-transition)
    //   val=15000 → 246   (presque nuit en fin de partie)
    // La courbe log donne une progression douce : rapide au début, s'aplatit en haut
    // (même principe que le smooth coloring Mandelbrot, recalibré pour un jeu)
    double result = log(val / 1800.0 + 1.0) * 110.0;
    if (result < 0.0)
        result = 0.0;
    if (result > 255.0)
        result = 255.0;
    return result;
}

// =============================================================
// helper_plat_freq — Fréquence d'oscillation par plateforme
// Entrée : ecx = index (int)
// Retour : xmm0 (double) — fréquence propre à chaque plateforme
//
// Chaque plateforme a sa fréquence unique pour éviter la
// synchronisation et créer un effet naturel/organique.
// =============================================================
__declspec(dllexport) double helper_plat_freq(int index)
{
    // Base : 0.006, variation par modulo 7 (nombre premier pour diversité)
    return 0.006 + (double)(index % 7) * 0.0015;
}

// =============================================================
// helper_sin — Wrapper sin() pour l'assembleur
// Entrée : xmm0 = angle (double, radians)
// Retour : xmm0 (double) = sin(angle) dans [-1.0, +1.0]
//
// Élimine le dernier x87 (fsin) de platforms.asm en déléguant
// au sin() de la CRT via le bridge C, conforme ABI Win64.
// =============================================================
__declspec(dllexport) double helper_sin(double angle)
{
    return sin(angle);
}