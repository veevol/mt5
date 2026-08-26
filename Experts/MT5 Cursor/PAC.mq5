//+------------------------------------------------------------------+
//|                                                          PAC.mq5 |
//|                    Pivot and Control — fase 1: deteksi Pivot     |
//|  Belum ada Control, area entry, atau order.                      |
//+------------------------------------------------------------------+
#property copyright "PAC"
#property version   "1.00"
#property description "PAC — deteksi Pivot Buy/Sell + penanda chart"
#property description "Fase 1: belum mengeksekusi order"

//+------------------------------------------------------------------+
//| TYPES                                                            |
//+------------------------------------------------------------------+
enum ENUM_PIVOT_SYMBOL
  {
   PIVOT_ARROW    = 0, // Panah
   PIVOT_TRIANGLE = 1, // Segitiga
   PIVOT_DOT      = 2, // Titik
   PIVOT_DIAMOND  = 3, // Belah ketupat
   PIVOT_THUMB    = 4  // Jempol
  };

enum ENUM_PIVOT_TYPE
  {
   PIVOT_BUY  = 1,
   PIVOT_SELL = -1
  };

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input group "=== Deteksi ==="
input ENUM_TIMEFRAMES InpDetectionTF = PERIOD_M1;  // Timeframe deteksi Pivot
input int             InpLookback    = 500;        // Jumlah bar yang discan

input group "=== Style Pivot ==="
input ENUM_PIVOT_SYMBOL InpPivotSymbol = PIVOT_ARROW; // Simbol penanda
input color             InpPivotColor  = clrYellow;   // Warna penanda
input int               InpGapPips     = 5;           // Offset (pips). Nanti dipakai juga untuk jarak ujung Base ke Atap/Lantai

//+------------------------------------------------------------------+
//| CONST                                                            |
//+------------------------------------------------------------------+
const string PREFIX_PB = "PAC_PB_";
const string PREFIX_PS = "PAC_PS_";

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

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
Pivot    g_pivots[];
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
   DrawPivots();
  }

//+------------------------------------------------------------------+
bool IsGreen(const MqlRates &r) { return(r.close > r.open); }
bool IsRed(const MqlRates &r)   { return(r.close < r.open); }

//+------------------------------------------------------------------+
int PivotArrowCode(const bool isBuy)
  {
   switch(InpPivotSymbol)
     {
      case PIVOT_TRIANGLE: return(isBuy ? 241 : 242);
      case PIVOT_DOT:      return(159);
      case PIVOT_DIAMOND:  return(117);
      case PIVOT_THUMB:    return(isBuy ? 67 : 68);
      default:             return(isBuy ? 233 : 234);
     }
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
void DrawPivots()
  {
   ObjectsDeleteAll(0, PREFIX_PB);
   ObjectsDeleteAll(0, PREFIX_PS);

   const double gap = MathMax(InpGapPips, 0) * PipSize();
   const int n = ArraySize(g_pivots);
   for(int i = 0; i < n; i++)
      CreateArrow(g_pivots[i], gap);

   ChartRedraw(0);
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
