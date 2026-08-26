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

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input group "=== Deteksi ==="
input ENUM_TIMEFRAMES InpDetectionTF = PERIOD_M1;  // Timeframe deteksi Pivot & Base
input int             InpLookback    = 500;        // Jumlah bar yang discan

input group "=== Style Pivot ==="
input ENUM_PIVOT_MARK InpPivotSymbol = MARK_LOZENGE_SM; // Simbol penanda
input color           InpPivotColor  = clrYellow;       // Warna penanda
input int             InpGapPips     = 5;               // Offset (pips). Nanti dipakai juga untuk jarak ujung Base ke Atap/Lantai

input group "=== Style Base ==="
input color InpBaseColor = clrWhite; // Warna garis High-Low Base

//+------------------------------------------------------------------+
//| CONST                                                            |
//+------------------------------------------------------------------+
const string PREFIX_PB  = "PAC_PB_";
const string PREFIX_PS  = "PAC_PS_";
const string PREFIX_RBR = "PAC_RBR_";
const string PREFIX_DBD = "PAC_DBD_";
const double BASE_BODY_RATIO = 0.5; // |Close-Open| ≤ rasio × (High-Low)

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

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
Pivot    g_pivots[];
Base     g_bases[];
datetime g_lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   ScanAndDraw();
   g_lastBarTime = iTime(_Symbol, InpDetectionTF, 0);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PREFIX_PB);
   ObjectsDeleteAll(0, PREFIX_PS);
   ObjectsDeleteAll(0, PREFIX_RBR);
   ObjectsDeleteAll(0, PREFIX_DBD);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   const datetime barTime = iTime(_Symbol, InpDetectionTF, 0);
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
   DrawPivots();
   DrawBases();
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
bool IsGreen(const MqlRates &r) { return(r.close > r.open); }
bool IsRed(const MqlRates &r)   { return(r.close < r.open); }
bool IsBase(const MqlRates &r)
  {
   return(MathAbs(r.close - r.open) <= BASE_BODY_RATIO * (r.high - r.low));
  }

//+------------------------------------------------------------------+
int PivotArrowCode(const bool isBuy)
  {
   int code = (int)InpPivotSymbol;
   if(!isBuy && (InpPivotSymbol == MARK_ARROW || InpPivotSymbol == MARK_TRIANGLE))
      code++;
   return(code);
  }

//+------------------------------------------------------------------+
double PipSize()
  {
   const double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
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
   const int copied = CopyRates(_Symbol, InpDetectionTF, 0, lookback, rates);
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
   const int copied = CopyRates(_Symbol, InpDetectionTF, 0, lookback, rates);
   if(copied < 4)
      return;
   ArraySetAsSeries(rates, false);

   const int lastClosed = copied - 2;

   //--- C2 butuh C1 di kiri dan C3 tertutup di kanan
   for(int i = 1; i < lastClosed; i++)
     {
      if(!IsBase(rates[i]))
         continue;

      if(IsGreen(rates[i - 1]) && IsGreen(rates[i + 1]))
         AddBase(rates[i], BASE_RBR, rates[i - 1].time, rates[i + 1].time);
      else if(IsRed(rates[i - 1]) && IsRed(rates[i + 1]))
         AddBase(rates[i], BASE_DBD, rates[i - 1].time, rates[i + 1].time);
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
