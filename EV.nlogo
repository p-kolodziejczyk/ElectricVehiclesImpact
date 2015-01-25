__includes["my-global.nls" "RunProcedures.nls"]
extensions [profiler]

to setup-square ;observer
  clear-all
  reset-ticks
  set-global-values
  setup-neighbourhoods
  setup-social-circle
  setup-area-user-impact
  distribute-income
  distribute-demand-capacity
  setup-EVs
  set-travel-parameters
  repeat 12 [go-traveling]
  update-plots
end

to profiler
setup-square           ;; set up the model
profiler:start         ;; start profiling
repeat 180 [ go ]       ;; run something you want to measure
profiler:stop          ;; stop profiling
print profiler:report  ;; view the results
end

to go ;observer
  ;cut-memory
  determine-used-capacity
  update-area-user-impact
  update-friendship-impact
  consider-buying-car
  go-traveling  
  update-monthly
  if (ticks > 0 AND remainder ticks 12 = 0) [update-yearly]
  tick  
end



to setup-neighbourhoods
  set-default-shape Transformers "Flag"
  set-default-shape Users "person"
  create-Transformers 1 [set level "NHtransformer" set color blue set size 20 set xcor round (min-pxcor + max-pxcor / 32)] ;create highest level transformer and assign it coordinates
  ask Transformers [hatch (6 + random 3) [set level "LVtransformer" set size 10  create-power-line-to myself [set thickness 1] set xcor round (xcor + max-pxcor / 14)]] ;create 6-8 lower level transformers and assign them X coorditanes, connecting to higher level one
  ask patches [set pcolor green]
  let aux 0
  ask Transformers with [level = "LVtransformer"][set ycor round (max-pycor - max-pycor / 7 - (aux * round (max-pycor / 4.1))) set aux aux + 1 ] ; Assign Y coordinates to LV transformers
  ask Transformers with [level = "LVtransformer"][set aux 0 hatch (2 + random 2) [set level "LVline" set size 5 create-power-line-to myself [set thickness 0.5] set xcor round (xcor + max-pxcor / 12) set ycor round (ycor + 12 - aux * 12) set aux aux + 1]] ;Each of LV transformers creates 2-3 power lines, which are also given coordinates and directed connection
  ask Transformers with [level = "LVline"][
    ask patches with [pycor = [ycor] of myself AND pxcor > [xcor] of myself][set pcolor blue]  ;color patches to imitate road
    set aux 0.9 hatch-HHs round ((21 / count Transformers with [level = "LVline"]) * (65 + random-poisson 22))[set shape "house" set color brown set size 3 create-power-line-to myself [hide-link] ;Make power lines create households proportionally to the number of lines so that the total is around 1800, make direct link
    set xcor xcor + round (aux) * 6  ;assign X coordinate to them
    ifelse (remainder (aux + 0.1) 1 = 0 ) [set ycor ycor + 4][set ycor ycor - 2] set aux aux + 0.5] ; assign Y coordinates to them on both sides of the road
  ]
  ask HHs [hatch-Users 1 [set xcor xcor + 2 set color black create-association-to myself]]; create users for each household and connect them
end

to setup-social-circle; observer
    ask Users [
    create-friendships-with Users with [self > myself and random-float count Users < average-number-friendships][hide-link]] ;create friendships among users so that their average amount to average-number-friendhsips 
    ask Users [set Preference random-float 1.0] ;give them initial value of preference
end

to setup-area-user-impact
  ask users
  [
    let i 0
    while [i <= size-of-area-influence / 6][ ;affect all other users within size-of-area-influence radius
      ask other Users in-radius (6 * i) with [distance myself > (6 * (i - 1))][ ;dividing this area into rings of 6 wide
        create-area_connection-to myself [set interval i hide-link] 
      ]
      set i i + 1     
    ]
  ]
end

to setup-EVs ; observer
  set-default-shape EVs "car"
  let AverageIncome (sum [Income] of users / count users / NHRichFactor)
  ask users [If ( random-normal ( 0.7 * Income / AverageIncome ) 1.5 > 0)[ hatch-EVs 1 [set ycor ycor - 3 create-association-to myself create-associations-to [out-link-neighbors] of myself]]]  
  ask users with [any? in-association-neighbors]
  [
    let prob_private 0
    let prob_lease 0
    ifelse IncSource = 0
    [
      set prob_private 0.8
      set prob_lease 0.15 
    ]
    [
      ifelse IncSource = 1
      [
        set prob_private 0.5
        set prob_lease 0.4   
      ]
      [
      set prob_private 0.2
      set prob_lease 0.1 
      ]
    ]
determine-ownership-type prob_private prob_lease
  ]    
end    
 
    
to determine-ownership-type [private lease] ;user    
    Ifelse random-float 1 > private
    [ 
      ask in-association-neighbors 
      [
        Ifelse random-float 1 > (lease / (1 - private))
        [
          set CarOwnership 2 set color violet set CarAge round (12 * random-normal 2 1) if CarAge < 0 [set CarAge 0]
        ]
        [
          set CarOwnership 1  set color magenta set CarAge round (12 * random-normal 2 1) if CarAge < 0 [set CarAge 0]
        ]
      ]
    ] ;; check company car or lease
    [ 
      ask in-association-neighbors [set CarOwnership 0 set color cyan set CarAge round (12 * random-normal 3 1.5) IF CarAge < 0 [set CarAge 0]] ;; set car as private car
    ]
end


to distribute-income
let alpha 484 / 114 ;set distribution parameter 
let lambda 1 / (114 / 22) ; mean - 22 and variance 114
ask n-of 10 users [set Income round(income-source * random-gamma alpha lambda)]  ;assign Income to 10 random users 
while [ any? users with [ Income = 0 ]] [ ; while there are any users with no income
  ask users with [ income != 0 ] [  ;ask users that already have income
      set alpha Income * Income / 22 ;assign mean of the distribution to their income,  swap previous variance with mean
      set lambda 1 / (22 / Income) ;recalculate distribution paremeters
      ask other users in-radius 6 with [ income = 0 ][set Income round(income-source * random-gamma alpha lambda)] ; assign randomized income to closest neighbours
      if any? users in-radius 30 with [ income = 0 ][ask one-of users in-radius 30 with [ income = 0 ][set Income round(income-source * random-gamma alpha lambda)]] ;and one random user further on
  ]
]
end

;procedure added not to repeat same code multiple times
to-report income-source ;user 
 let RSource random 100
 If RSource <= (12 + (36 / NHRichFactor)) [set IncSource 0  set color lime report 1];set person as unemployed/retired etc., return income multiplier 
 If RSource >= (100 - 12 * NHRichFactor) [set IncSource 2  set color yellow report 1.3]  ;set person as self-employed, return income multiplier
 set IncSource 1 set color black report 1.15 ;set user as employed, return income multiplier
end

to distribute-demand-capacity
  ;Distrubute demand to households
  let HHBegin 400 ;; the average energy use of a household in 2014 that does not change during runtime
  ask HHs [set HHAverage random-normal HHBegin 50  set HHPeak round (HHAverage * HHFactor)] ;set average peak energy use for all households with std. deviation of 50 
  
  ;Distribute capacity to low voltage lines
  ask Transformers with [level = "LVline"] [
    let HHPeakIn sum [HHPeak] of in-power-line-neighbors
    set Capacity round (NHFactor * LVFactor * HHPeakIn)
    ]
  
  ;Distribute capacity to low voltage transformers
  ask Transformers with [level = "LVtransformer"][
    let HHPeakIn 0
    ask in-power-line-neighbors [set HHPeakIn HHPeakIn + sum [HHPeak] of in-power-line-neighbors]
    set Capacity round (NHFactor * TFFactor * HHPeakIn)]
  
  ;Distribute capacity to neighbourhood transformer
  ask Transformers with [level = "NHtransformer"][
    set Capacity round (NHFactor * (sum [HHPeak] of HHs))
  ]

end

to set-travel-parameters ;; inits the parameter that define the travel patterns of the user
  ask users with [any? in-association-neighbors][
    set trip_memory [] ;; init memory to an empty list
    set commute_probability random-normal 0.8 0.1  ;; set the commute probability 
    ;;next two lines to check that the probability still stays between 5 and 100%
    if (commute_probability > 1) [set commute_probability 1] 
    if (commute_probability < 0.05) [set commute_probability  0.05]
    
    ;; set the average commute distance of the user with a lower bound of 5km
    set commute_average  random-normal 40 10
    if (commute_average < 5) [set commute_average 5]
 
    ;;set the probability of going on a longer trip. can only stay in a range of 0-100%
    set long_dist_probability random-normal 0.2 0.1 
    if (long_dist_probability < 0) [set long_dist_probability 0]
    if (long_dist_probability > 1) [set long_dist_probability 1]
    
    ;; set the average distance traveled when going on a non commuting trip with a lower bound 10km
    set long_dist random-normal 100 50
    if (long_dist < 10) [set long_dist 10]
    ]
end
@#$#@#$#@
GRAPHICS-WINDOW
408
10
1921
1064
250
170
3.0
1
10
1
1
1
0
1
1
1
-250
250
-170
170
0
0
1
ticks
30.0

BUTTON
13
153
76
186
NIL
Go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
11
192
90
225
Go Once
Go
NIL
1
T
OBSERVER
NIL
G
NIL
NIL
1

BUTTON
15
65
115
98
NIL
setup-square
NIL
1
T
OBSERVER
NIL
S
NIL
NIL
1

MONITOR
309
16
379
61
NIL
count HHs
17
1
11

SLIDER
171
340
396
373
average-number-friendships
average-number-friendships
0
60
15
1
1
NIL
HORIZONTAL

MONITOR
280
192
388
237
NIL
count friendships
17
1
11

SLIDER
171
411
382
444
size-of-area-influence
size-of-area-influence
0
60
12
6
1
patches
HORIZONTAL

SLIDER
172
446
344
479
user-area-impact
user-area-impact
0
0.1
0.01
0.005
1
NIL
HORIZONTAL

SLIDER
171
375
343
408
impact-on-friendships
impact-on-friendships
0
0.1
0.03
0.01
1
NIL
HORIZONTAL

PLOT
10
575
384
787
income disparity histogram
income value
number
0.0
250.0
0.0
50.0
true
false
"" ""
PENS
"default" 5.0 1 -16777216 true "" "histogram [Income] of users"

SLIDER
-3
340
169
373
NHFactor
NHFactor
1.0
1.6
1.5
0.1
1
NIL
HORIZONTAL

SLIDER
-2
409
170
442
LVFactor
LVFactor
0.5
2.5
1.3
0.1
1
NIL
HORIZONTAL

SLIDER
0
373
172
406
TFFactor
TFFactor
0.5
2.5
1.4
0.1
1
NIL
HORIZONTAL

SLIDER
-2
446
170
479
NHRichFactor
NHRichFactor
0.4
3
0.8
0.1
1
NIL
HORIZONTAL

PLOT
9
792
384
1029
Capacity 
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "plot sum [Capacity] of Transformers" "plot sum [Capacity] of Transformers"
"pen-1" 1.0 0 -7500403 true "plot sum [Overcapacity] of Transformers" "plot sum [Overcapacity] of Transformers"

PLOT
10
1035
387
1261
Household demand
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot sum [HHAverage] of HHs"
"pen-1" 1.0 0 -7500403 true "" "plot sum [HHPeak] of HHs"
"pen-2" 1.0 0 -2674135 true "" "plot sum [EVPeak] of EVs"

MONITOR
310
65
377
110
cars
count EVs
17
1
11

PLOT
411
1073
846
1273
Car Ownership
NIL
NIL
0.0
1.0
0.0
500.0
true
true
"" ""
PENS
"Own Car" 1.0 0 -11221820 true "" "plot count EVs with [CarOwnership = 0]"
"Lease Car" 1.0 0 -5825686 true "" "plot count EVs with [CarOwnership = 1]"
"Company Car" 1.0 0 -8630108 true "" "plot count EVs with [CarOwnership = 2]"

PLOT
850
1072
1166
1272
Income source distribution
NIL
NIL
0.0
1.0
0.0
1000.0
true
true
"" ""
PENS
"Unemployed/retired" 1.0 0 -13840069 true "" "plot count users with [IncSource = 0]"
"Employed" 1.0 0 -16777216 true "" "plot count users with [IncSource = 1]"
"Self-employed" 1.0 0 -1184463 true "" "plot count users with [IncSource = 2]"

MONITOR
310
113
377
158
EVs
count EVs with [BatteryCapacity > 0]
17
1
11

SLIDER
0
478
172
511
tax_global
tax_global
0
5000
2500
1
1
NIL
HORIZONTAL

SLIDER
-1
514
230
547
global_battery_price_init
global_battery_price_init
0
500
120
1
1
NIL
HORIZONTAL

SLIDER
175
479
371
512
battery_price_drop
battery_price_drop
0
0.25
0.01
0.01
1
NIL
HORIZONTAL

BUTTON
14
103
85
136
NIL
profiler
NIL
1
T
OBSERVER
NIL
P
NIL
NIL
1

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270

@#$#@#$#@
NetLogo 5.1.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="experiment2" repetitions="20" runMetricsEveryStep="true">
    <setup>setup-square</setup>
    <go>go</go>
    <timeLimit steps="180"/>
    <metric>sum [Overcapacity] of Transformers</metric>
    <metric>count HHs</metric>
    <metric>count EVs</metric>
    <metric>count EVs with [BatteryCapacity &gt; 0]</metric>
    <metric>mean [BatteryCapacity] of EVs with [BatteryCapacity &gt; 0]</metric>
    <metric>median [BatteryCapacity] of EVs with [BatteryCapacity &gt; 0]</metric>
    <enumeratedValueSet variable="LVFactor">
      <value value="1.3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="NHFactor">
      <value value="1.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="size-of-area-influence">
      <value value="18"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="user-area-impact">
      <value value="0.01"/>
      <value value="0.05"/>
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tax_global">
      <value value="2500"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="global_battery_price_init">
      <value value="120"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="TFFactor">
      <value value="1.4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="average-number-friendships">
      <value value="15"/>
      <value value="30"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="battery_price_drop">
      <value value="0.01"/>
      <value value="0.05"/>
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="NHRichFactor">
      <value value="0.8"/>
      <value value="1.6"/>
      <value value="2.4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="impact-on-friendships">
      <value value="0.03"/>
      <value value="0.06"/>
      <value value="0.09"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

@#$#@#$#@
0
@#$#@#$#@
