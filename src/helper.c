#include <math.h>

// perlin 2D avec smoothstep et hash Jenkins-style
__declspec(dllexport) double helper_perlin2d(double x, double y)
{
    int xi = (int)floor(x) & 255;
    int yi = (int)floor(y) & 255;
    double xf = x - floor(x);
    double yf = y - floor(y);

    double u = xf * xf * xf * (xf * (xf * 6.0 - 15.0) + 10.0);
    double v = yf * yf * yf * (yf * (yf * 6.0 - 15.0) + 10.0);

    int h00 = ((xi * 1619 + yi * 31337 + 1013904223) * 1664525) & 0x7FFFFFFF;
    int h10 = (((xi + 1) * 1619 + yi * 31337 + 1013904223) * 1664525) & 0x7FFFFFFF;
    int h01 = ((xi * 1619 + (yi + 1) * 31337 + 1013904223) * 1664525) & 0x7FFFFFFF;
    int h11 = (((xi + 1) * 1619 + (yi + 1) * 31337 + 1013904223) * 1664525) & 0x7FFFFFFF;

    double g00 = (h00 / 1073741824.0) - 1.0;
    double g10 = (h10 / 1073741824.0) - 1.0;
    double g01 = (h01 / 1073741824.0) - 1.0;
    double g11 = (h11 / 1073741824.0) - 1.0;

    double ix0 = g00 + u * (g10 - g00);
    double ix1 = g01 + u * (g11 - g01);
    return ix0 + v * (ix1 - ix0);
}

// smooth coloring Mandelbrot adapte pour l'altitude du jeu
__declspec(dllexport) double helper_smooth_log(double val)
{
    if (val <= 0.0)
        return 0.0;
    double result = log(val / 1800.0 + 1.0) * 110.0;
    if (result > 255.0)
        result = 255.0;
    return result;
}

// frequence d'oscillation par index de plateforme
// modulo 7 (premier) pour eviter les sous-harmoniques
__declspec(dllexport) double helper_plat_freq(int index)
{
    return 0.006 + (double)(index % 7) * 0.0015;
}

__declspec(dllexport) double helper_sin(double angle)
{
    return sin(angle);
}
