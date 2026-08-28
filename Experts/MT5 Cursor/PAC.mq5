//+------------------------------------------------------------------+
//|                                                          PAC.mq5 |
//|          Pivot and Control — fase 2: Pivot + candle Base         |
//|  Belum ada Control (overlap Pivot), area entry, atau order.      |
//+------------------------------------------------------------------+
#property copyright "PAC"
#property version   "1.00"
#property description "PAC — deteksi Pivot + candle Base RBR/DBD"
#property description "Fase 2: belum Control, area entry, atau order"

//+------------------------------------------------------------------+
//| TYPES                                                            |
//+------------------------------------------------------------------+
enum ENUM_PIVOT_TYPE
  {
   PIVOT_BUY  = 1,
   PIVOT_SELL = -1
  };

enum ENUM_PIVOT_MARK
  {
   MARK_LOZENGE_SM = 115, // Belah ketupat kecil
   MARK_LOZENGE    = 116, // Belah ketupat
   MARK_DIAMOND    = 117, // Diamond
   MARK_DIAMOND_SM = 119, // Diamond kecil
   MARK_DOT        = 159, // Titik
   MARK_CIRCLE     = 108, // Lingkaran
   MARK_ARROW      = 233, // Panah atas/bawah
   MARK_TRIANGLE   = 241  // Segitiga atas/bawah
  };

enum ENUM_BASE_TYPE
  {
   BASE_RBR = 1,  // Rally-Base-Rally (untuk Pivot Buy)
   BASE_DBD = -1  // Drop-Base-Drop (untuk Pivot Sell)
  };

enum ENUM_DETECTION_TF
  {
   TF_AUTO = 0,           // Auto
   TF_M1   = PERIOD_M1,   // 1 Minute
   TF_M2   = PERIOD_M2,   // 2 Minutes
   TF_M3   = PERIOD_M3,   // 3 Minutes
   TF_M4   = PERIOD_M4,   // 4 Minutes
   TF_M5   = PERIOD_M5,   // 5 Minutes
   TF_M6   = PERIOD_M6,   // 6 Minutes
   TF_M10  = PERIOD_M10,  // 10 Minutes
   TF_M12  = PERIOD_M12,  // 12 Minutes
   TF_M15  = PERIOD_M15,  // 15 Minutes
   TF_M20  = PERIOD_M20,  // 20 Minutes
   TF_M30  = PERIOD_M30,  // 30 Minutes
   TF_H1   = PERIOD_H1,   // 1 Hour
   TF_H2   = PERIOD_H2,   // 2 Hours
   TF_H3   = PERIOD_H3,   // 3 Hours
   TF_H4   = PERIOD_H4,   // 4 Hours
   TF_H6   = PERIOD_H6,   // 6 Hours
   TF_H8   = PERIOD_H8,   // 8 Hours
   TF_H12  = PERIOD_H12,  // 12 Hours
   TF_D1   = PERIOD_D1,   // Daily
   TF_W1   = PERIOD_W1,   // Weekly
   TF_MN1  = PERIOD_MN1   // Monthly
  };

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input group "=== Deteksi ==="
input ENUM_DETECTION_TF InpDetectionTF = TF_AUTO;         // TF Pivot & Base
input int               InpLookback    = 500;             // Jml bar scan
input ENUM_PIVOT_MARK   InpPivotSymbol = MARK_LOZENGE_SM; // Pivot - Style Tag
input int               InpGapPips     = 5;               // Pivot - Offset Tag (pips)
input color             InpPivotColor  = clrYellow;       // Pivot - Warna Tag
input color             InpBaseColor   = clrWhite;        // Base - Warna Candle
input color             InpSupportColor = clrForestGreen; // RBR - Warna Zona
input color             InpResistColor  = clrFireBrick;   // DBD - Warna Zona

//+------------------------------------------------------------------+
//| CONST                                                            |
//+------------------------------------------------------------------+
const string PREFIX_PB  = "PAC_PB_";
const string PREFIX_PS  = "PAC_PS_";
const string PREFIX_RBR = "PAC_RBR_";
const string PREFIX_DBD = "PAC_DBD_";
const string PREFIX_SUP = "PAC_SUP_";
const string PREFIX_RES = "PAC_RES_";
const double BASE_BODY_RATIO  = 0.5; // |Close-Open| ≤ rasio × (High-Low)
const int    IMPULSE_BODY_PCT = 50;  // Body minimal rally/drop (% dari High-Low)

struct Pivot
  {
   datetime        time;
   double          open;
   double          high;
   double          low;
   double          close;
   ENUM_PIVOT_TYPE type;
   datetime        confirm1;
   datetime        confirm2;
  };

struct Base
  {
   datetime       time;
   double         open;
   double         high;
   double         low;
   double         close;
   ENUM_BASE_TYPE type;
   datetime       c1;
   datetime       c3;
  };

struct SrZone
  {
   datetime left;
   datetime right;
   double   high;
   double   low;
   bool     isSupport;
  };

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
Pivot            g_pivots[];
Base             g_bases[];
SrZone           g_zones[];
datetime         g_lastBarTime = 0;
ENUM_TIMEFRAMES  g_usedTF      = PERIOD_CURRENT;

//+------------------------------------------------------------------+
ENUM_TIMEFRAMES DetectionTF()
  {
   if(InpDetectionTF == TF_AUTO)
      return((ENUM_TIMEFRAMES)Period());
   return((ENUM_TIMEFRAMES)InpDetectionTF);
  }

//+------------------------------------------------------------------+
void DeleteMarks()
  {
   ObjectsDeleteAll(0, PREFIX_PB);
   ObjectsDeleteAll(0, PREFIX_PS);
   ObjectsDeleteAll(0, PREFIX_RBR);
   ObjectsDeleteAll(0, PREFIX_DBD);
   ObjectsDeleteAll(0, PREFIX_SUP);
   ObjectsDeleteAll(0, PREFIX_RES);
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   g_usedTF = DetectionTF();
   ScanAndDraw();
   g_lastBarTime = iTime(_Symbol, g_usedTF, 0);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   DeleteMarks();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   const ENUM_TIMEFRAMES tf = DetectionTF();
   if(tf != g_usedTF)
     {
      DeleteMarks();
      g_usedTF      = tf;
      g_lastBarTime = 0;
      ScanAndDraw();
      g_lastBarTime = iTime(_Symbol, tf, 0);
      return;
     }

   const datetime barTime = iTime(_Symbol, tf, 0);
   if(barTime == 0 || barTime == g_lastBarTime)
      return;
   g_lastBarTime = barTime;
   ScanAndDraw();
  }

//+------------------------------------------------------------------+
void ScanAndDraw()
  {
   ScanPivots();
   ScanBases();
   ScanSrZones();
   DrawPivots();
   DrawBases();
   DrawSrZones();
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
bool IsGreen(const MqlRates &r) { return(r.close > r.open); }
bool IsRed(const MqlRates &r)   { return(r.close < r.open); }
bool IsBase(const MqlRates &r)
  {
   return(MathAbs(r.close - r.open) <= BASE_BODY_RATIO * (r.high - r.low));
  }
bool IsImpulse(const MqlRates &r)
  {
   const double range = r.high - r.low;
   if(range <= 0.0)
      return(false);
   const double ratio = MathMax(IMPULSE_BODY_PCT, 0) / 100.0;
   return(MathAbs(r.close - r.open) >= ratio * range);
  }
bool IsRally(const MqlRates &r) { return(IsGreen(r) && IsImpulse(r)); }
bool IsDrop(const MqlRates &r)  { return(IsRed(r) && IsImpulse(r)); }

//+------------------------------------------------------------------+
int PivotArrowCode(const bool isBuy)
  {
   int code = (int)InpPivotSymbol;
   if(!isBuy && (InpPivotSymbol == MARK_ARROW || InpPivotSymbol == MARK_TRIANGLE))
      code++;
   return(code);
  }

//+------------------------------------------------------------------+
bool IsGoldSymbol()
  {
   string s = _Symbol;
   StringToUpper(s);
   if(StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0)
      return(true);
   string base = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   StringToUpper(base);
   return(base == "XAU" || base == "GOLD");
  }

//+------------------------------------------------------------------+
double PipSize()
  {
   const double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(IsGoldSymbol())
      return((digits == 3) ? (pt * 100.0) : (pt * 10.0));
   if(digits == 3 || digits == 5)
      return(pt * 10.0);
   return(pt);
  }

//+------------------------------------------------------------------+
void AddPivot(const MqlRates &bar, const ENUM_PIVOT_TYPE type,
              const datetime c1, const datetime c2)
  {
   const int n = ArraySize(g_pivots);
   ArrayResize(g_pivots, n + 1, 64);
   g_pivots[n].time     = bar.time;
   g_pivots[n].open     = bar.open;
   g_pivots[n].high     = bar.high;
   g_pivots[n].low      = bar.low;
   g_pivots[n].close    = bar.close;
   g_pivots[n].type     = type;
   g_pivots[n].confirm1 = c1;
   g_pivots[n].confirm2 = c2;
  }

//+------------------------------------------------------------------+
void ScanPivots()
  {
   ArrayResize(g_pivots, 0);

   const int lookback = MathMax(InpLookback, 4);
   MqlRates rates[];
   const int copied = CopyRates(_Symbol, DetectionTF(), 0, lookback, rates);
   if(copied < 4)
      return;
   ArraySetAsSeries(rates, false);

   const int lastClosed = copied - 2;

   int      buyCand   = -1;
   int      buyGreens = 0;
   datetime buyConf1  = 0;

   int      sellCand = -1;
   int      sellReds = 0;
   datetime sellConf1 = 0;

   for(int i = 1; i <= lastClosed; i++)
     {
      //--- Pivot Buy: rolling candidate, 2 candle hijau konfirmasi
      if(buyCand >= 0)
        {
         if(rates[i].low < rates[buyCand].low)
           {
            buyCand   = i;
            buyGreens = 0;
            buyConf1  = 0;
           }
         else if(IsGreen(rates[i]) && rates[i].open > rates[buyCand].close)
           {
            buyGreens++;
            if(buyGreens == 1)
               buyConf1 = rates[i].time;
            else
              {
               AddPivot(rates[buyCand], PIVOT_BUY, buyConf1, rates[i].time);
               buyCand   = -1;
               buyGreens = 0;
               buyConf1  = 0;
              }
           }
        }
      if(buyCand < 0 && rates[i].low < rates[i - 1].low)
        {
         buyCand   = i;
         buyGreens = 0;
         buyConf1  = 0;
        }

      //--- Pivot Sell: cermin dari Buy
      if(sellCand >= 0)
        {
         if(rates[i].high > rates[sellCand].high)
           {
            sellCand  = i;
            sellReds  = 0;
            sellConf1 = 0;
           }
         else if(IsRed(rates[i]) && rates[i].open < rates[sellCand].close)
           {
            sellReds++;
            if(sellReds == 1)
               sellConf1 = rates[i].time;
            else
              {
               AddPivot(rates[sellCand], PIVOT_SELL, sellConf1, rates[i].time);
               sellCand  = -1;
               sellReds  = 0;
               sellConf1 = 0;
              }
           }
        }
      if(sellCand < 0 && rates[i].high > rates[i - 1].high)
        {
         sellCand  = i;
         sellReds  = 0;
         sellConf1 = 0;
        }
     }
  }

//+------------------------------------------------------------------+
void AddBase(const MqlRates &bar, const ENUM_BASE_TYPE type,
             const datetime c1, const datetime c3)
  {
   const int n = ArraySize(g_bases);
   ArrayResize(g_bases, n + 1, 64);
   g_bases[n].time  = bar.time;
   g_bases[n].open  = bar.open;
   g_bases[n].high  = bar.high;
   g_bases[n].low   = bar.low;
   g_bases[n].close = bar.close;
   g_bases[n].type  = type;
   g_bases[n].c1    = c1;
   g_bases[n].c3    = c3;
  }

//+------------------------------------------------------------------+
void ScanBases()
  {
   ArrayResize(g_bases, 0);

   const int lookback = MathMax(InpLookback, 4);
   MqlRates rates[];
   const int copied = CopyRates(_Symbol, DetectionTF(), 0, lookback, rates);
   if(copied < 4)
      return;
   ArraySetAsSeries(rates, false);

   const int lastClosed = copied - 2;

   //--- C2 butuh C1 di kiri dan C3 tertutup di kanan
   for(int i = 1; i < lastClosed; i++)
     {
      if(!IsBase(rates[i]))
         continue;

      if(IsRally(rates[i - 1]) && IsRally(rates[i + 1]) && rates[i + 1].close > rates[i].high)
         AddBase(rates[i], BASE_RBR, rates[i - 1].time, rates[i + 1].time);
      else if(IsDrop(rates[i - 1]) && IsDrop(rates[i + 1]) && rates[i + 1].close < rates[i].low)
         AddBase(rates[i], BASE_DBD, rates[i - 1].time, rates[i + 1].time);
     }
  }

//+------------------------------------------------------------------+
void CoverAdd(double &cLo[], double &cHi[], int &n, double a, double b)
  {
   const double eps = _Point;
   int i = 0;
   while(i < n)
     {
      if(b + eps < cLo[i] || a - eps > cHi[i])
        {
         i++;
         continue;
        }
      a = MathMin(a, cLo[i]);
      b = MathMax(b, cHi[i]);
      for(int k = i; k < n - 1; k++)
        {
         cLo[k] = cLo[k + 1];
         cHi[k] = cHi[k + 1];
        }
      n--;
      i = 0;
     }
   ArrayResize(cLo, n + 1);
   ArrayResize(cHi, n + 1);
   cLo[n] = a;
   cHi[n] = b;
   n++;
  }

//+------------------------------------------------------------------+
void CoverClipAdd(double &cLo[], double &cHi[], int &n,
                  const double a, const double b,
                  const double zoneLow, const double zoneHigh)
  {
   const double lo = MathMax(MathMin(a, b), zoneLow);
   const double hi = MathMin(MathMax(a, b), zoneHigh);
   if(hi > lo)
      CoverAdd(cLo, cHi, n, lo, hi);
  }

//+------------------------------------------------------------------+
bool CoverFull(const double &cLo[], const double &cHi[], const int n,
               const double zoneLow, const double zoneHigh)
  {
   if(n <= 0)
      return(false);

   const double eps = _Point;
   int order[];
   ArrayResize(order, n);
   for(int i = 0; i < n; i++)
      order[i] = i;
   for(int i = 0; i < n - 1; i++)
      for(int k = i + 1; k < n; k++)
         if(cLo[order[k]] < cLo[order[i]])
           {
            const int tmp = order[i];
            order[i] = order[k];
            order[k] = tmp;
           }

   double curLo = cLo[order[0]];
   double curHi = cHi[order[0]];
   for(int i = 1; i < n; i++)
     {
      const int k = order[i];
      if(cLo[k] <= curHi + eps)
         curHi = MathMax(curHi, cHi[k]);
      else
        {
         if(curLo <= zoneLow + eps && curHi >= zoneHigh - eps)
            return(true);
         curLo = cLo[k];
         curHi = cHi[k];
        }
     }
   return(curLo <= zoneLow + eps && curHi >= zoneHigh - eps);
  }

//+------------------------------------------------------------------+
datetime ZoneRightTime(const MqlRates &rates[], const int copied, const int lastBaseIdx,
                       const double zoneHigh, const double zoneLow, const bool isSupport)
  {
   const int start = lastBaseIdx + 2; // skip Base + leg (C3)
   if(start >= copied)
      return(rates[copied - 1].time);

   double cLo[], cHi[];
   int n = 0;
   bool painting = false;
   double prevClose = 0.0;

   for(int j = start; j < copied; j++)
     {
      if(!painting)
        {
         const bool returned = isSupport
                               ? (rates[j].close < zoneHigh)
                               : (rates[j].close > zoneLow);
         if(!returned)
            continue;
         painting = true;
        }
      else
         CoverClipAdd(cLo, cHi, n, prevClose, rates[j].open, zoneLow, zoneHigh);

      CoverClipAdd(cLo, cHi, n,
                   MathMin(rates[j].open, rates[j].close),
                   MathMax(rates[j].open, rates[j].close),
                   zoneLow, zoneHigh);
      prevClose = rates[j].close;

      if(CoverFull(cLo, cHi, n, zoneLow, zoneHigh))
         return(rates[j].time);
     }
   return(rates[copied - 1].time);
  }

//+------------------------------------------------------------------+
void AddSrZone(const datetime left, const datetime right, const double hi, const double lo,
               const bool isSupport)
  {
   const int n = ArraySize(g_zones);
   ArrayResize(g_zones, n + 1, 32);
   g_zones[n].left      = left;
   g_zones[n].right     = right;
   g_zones[n].high      = hi;
   g_zones[n].low       = lo;
   g_zones[n].isSupport = isSupport;
  }

//+------------------------------------------------------------------+
void ScanSrZones()
  {
   ArrayResize(g_zones, 0);

   const int n = ArraySize(g_bases);
   if(n <= 0)
      return;

   const int lookback = MathMax(InpLookback, 4);
   MqlRates rates[];
   const int copied = CopyRates(_Symbol, DetectionTF(), 0, lookback, rates);
   if(copied < 4)
      return;
   ArraySetAsSeries(rates, false);

   int idx[];
   ArrayResize(idx, n);
   int ri = 0;
   for(int b = 0; b < n; b++)
     {
      while(ri < copied && rates[ri].time < g_bases[b].time)
         ri++;
      idx[b] = (ri < copied && rates[ri].time == g_bases[b].time) ? ri : -1;
     }

   int s = 0;
   while(s < n)
     {
      if(idx[s] < 0)
        {
         s++;
         continue;
        }
      int e = s;
      double hi = g_bases[s].high;
      double lo = g_bases[s].low;
      while(e + 1 < n && idx[e] >= 0 && idx[e + 1] == idx[e] + 1)
        {
         e++;
         if(g_bases[e].high > hi)
            hi = g_bases[e].high;
         if(g_bases[e].low < lo)
            lo = g_bases[e].low;
        }
      AddSrZone(g_bases[s].time,
                ZoneRightTime(rates, copied, idx[e], hi, lo,
                              g_bases[s].type == BASE_RBR),
                hi, lo,
                g_bases[s].type == BASE_RBR);
      s = e + 1;
     }
  }

//+------------------------------------------------------------------+
void DrawPivots()
  {
   ObjectsDeleteAll(0, PREFIX_PB);
   ObjectsDeleteAll(0, PREFIX_PS);

   const double gap = MathMax(InpGapPips, 0) * PipSize();
   const int n = ArraySize(g_pivots);
   for(int i = 0; i < n; i++)
      CreateArrow(g_pivots[i], gap);
  }

//+------------------------------------------------------------------+
void CreateArrow(const Pivot &p, const double gap)
  {
   const bool isBuy = (p.type == PIVOT_BUY);
   const string name = (isBuy ? PREFIX_PB : PREFIX_PS) + IntegerToString((long)p.time);
   const double price = isBuy ? (p.low - gap) : (p.high + gap);

   if(!ObjectCreate(0, name, OBJ_ARROW, 0, p.time, price))
      return;

   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, PivotArrowCode(isBuy));
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, isBuy ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpPivotColor);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
                   StringFormat("%s\n%s\nO=%s H=%s L=%s C=%s\nConf: %s | %s",
                                isBuy ? "PAC Pivot Buy" : "PAC Pivot Sell",
                                TimeToString(p.time, TIME_DATE | TIME_MINUTES),
                                DoubleToString(p.open, _Digits),
                                DoubleToString(p.high, _Digits),
                                DoubleToString(p.low, _Digits),
                                DoubleToString(p.close, _Digits),
                                TimeToString(p.confirm1, TIME_DATE | TIME_MINUTES),
                                TimeToString(p.confirm2, TIME_DATE | TIME_MINUTES)));
  }

//+------------------------------------------------------------------+
void DrawBases()
  {
   ObjectsDeleteAll(0, PREFIX_RBR);
   ObjectsDeleteAll(0, PREFIX_DBD);

   const int n = ArraySize(g_bases);
   for(int i = 0; i < n; i++)
      CreateBaseLine(g_bases[i]);
  }

//+------------------------------------------------------------------+
void CreateBaseLine(const Base &b)
  {
   const bool isRbr = (b.type == BASE_RBR);
   const string name = (isRbr ? PREFIX_RBR : PREFIX_DBD) + IntegerToString((long)b.time);

   if(!ObjectCreate(0, name, OBJ_TREND, 0, b.time, b.high, b.time, b.low))
      return;

   ObjectSetInteger(0, name, OBJPROP_COLOR, InpBaseColor);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
                   StringFormat("%s\n%s\nO=%s H=%s L=%s C=%s\nC1: %s | C3: %s",
                                isRbr ? "PAC Base RBR" : "PAC Base DBD",
                                TimeToString(b.time, TIME_DATE | TIME_MINUTES),
                                DoubleToString(b.open, _Digits),
                                DoubleToString(b.high, _Digits),
                                DoubleToString(b.low, _Digits),
                                DoubleToString(b.close, _Digits),
                                TimeToString(b.c1, TIME_DATE | TIME_MINUTES),
                                TimeToString(b.c3, TIME_DATE | TIME_MINUTES)));
  }

//+------------------------------------------------------------------+
void DrawSrZones()
  {
   ObjectsDeleteAll(0, PREFIX_SUP);
   ObjectsDeleteAll(0, PREFIX_RES);

   const int n = ArraySize(g_zones);
   for(int i = 0; i < n; i++)
      CreateSrRect(g_zones[i]);
  }

//+------------------------------------------------------------------+
void CreateSrRect(const SrZone &z)
  {
   const string name = (z.isSupport ? PREFIX_SUP : PREFIX_RES) + IntegerToString((long)z.left);

   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, z.left, z.high, z.right, z.low))
      return;

   ObjectSetInteger(0, name, OBJPROP_COLOR, z.isSupport ? InpSupportColor : InpResistColor);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
                   StringFormat("%s\n%s -> %s\nH=%s L=%s",
                                z.isSupport ? "PAC Support" : "PAC Resisten",
                                TimeToString(z.left, TIME_DATE | TIME_MINUTES),
                                TimeToString(z.right, TIME_DATE | TIME_MINUTES),
                                DoubleToString(z.high, _Digits),
                                DoubleToString(z.low, _Digits)));
  }

//+------------------------------------------------------------------+
