# EmpirBus / RMDS DataItem ID catalog

The name→ID map for the DataItem cells used by LightHouse "digital switching" pages
is **not published in plain form** anywhere — it lives inside the EmpirBus Graphic
tool. The official Raymarine forum guide this project is based on
([TG11](#source), see the README) tells you to build a page in EmpirBus Graphic and
read the IDs out of the exported package.

That's exactly how the table below was produced: load the blank `.EBP` project
(attached to the TG11 thread) in **EmpirBus Graphic**, drop in every DataItem you're
interested in from the repertoire, export the **RMDS** package, and read each
`m_Name` ↔ `m_DataItemID` pair straight out of the exported page QML. No proprietary
files are redistributed here — just the resulting numbers, which are facts.

Bind a native cell to one of these with `m_DataItemID` (and `m_PrimaryDataItemInstance`
for instanced types — engine 0/1, tank 0/1…):

```qml
DigitalValueDataItemCenterAligned {
    m_Name: "Coolant Temperature"
    m_DataItemID: 79; m_PrimaryDataItemInstance: 0   // instance 0 = port engine
}
```

## The map (as extracted this way)

This is the set we needed; the full catalog is larger and is read the same way.
Instanced items (engines, tanks, battery banks, AC lines) repeat per instance.

| ID | DataItem | Notes |
|---:|---|---|
| 3   | Fresh Water Level | tank, instanced |
| 5   | Black Water Level | tank, instanced |
| 19  | Apparent Wind Speed | |
| 22  | Apparent Wind Angle | |
| 45  | Water Depth | |
| 55  | Water Temperature | |
| 58  | Air Temperature | |
| 73  | RPM | engine, instanced |
| 74  | Boost Pressure | engine |
| 75  | Oil Temperature | engine |
| 76  | Oil Pressure | engine |
| 77  | Alternator Voltage | engine |
| 78  | Coolant Pressure | engine |
| 79  | Coolant Temperature | engine |
| 80  | Engine Load | engine |
| 81  | Engine Hours | engine |
| 83  | Engine Fuel Rate | engine |
| 84  | Inst. Fuel Economy | — note there are **two** economy items |
| 85  | Avg. Fuel Rate | |
| 86  | Fuel Pressure | engine |
| 87  | Fuel Level | tank, instanced |
| 88  | Fuel Volume | |
| 89  | Total Fuel Level | |
| 90  | Total Fuel | |
| 91  | Transmission Gear | |
| 92  | Transmission Oil Pressure | |
| 93  | Transmission Oil Temperature | |
| 94  | Pressure | barometric |
| 95  | Humidity | |
| 103 | Total Fuel Rate | |
| 104 | Fuel Economy | the second economy item — check which you want |
| 106 | Battery Current | bank, instanced |
| 107 | Battery Voltage | bank, instanced |
| 108 | Battery Temperature | bank, instanced |
| 131 | DC State of Charge | |
| 132 | DC Time Remaining | |
| 137 | AC Input Voltage Line 1 | AC, per line |
| 138 | AC Input Voltage Line 2 | |
| 139 | AC Input Voltage Line 3 | |
| 140 | AC Input Current Line 1 | |
| 141 | AC Input Current Line 2 | |
| 142 | AC Input Current Line 3 | |
| 143 | AC Input Frequency Line 1 | |
| 144 | AC Input Frequency Line 2 | |
| 145 | AC Input Frequency Line 3 | |
| 146 | AC Input Real Power Line 1 | |
| 155 | Charger Operating State | |
| 156 | Charger Enabled / Disabled | |
| 166 | AC Output Real Power Line 1 | |
| 167 | AC Output Real Power Line 2 | |
| 168 | AC Output Real Power Line 3 | |

> **Gotcha:** two "Fuel Economy" items exist — `84 = Inst. Fuel Economy` and
> `104 = Fuel Economy`. Pick deliberately. `86 = Fuel Pressure` also surprises people.

<a name="source"></a>
**Source of the method:** the Raymarine forum guide *"[TG11] Creating custom data pages
on Lighthouse 2 and Lighthouse 3 MFDs"* by Tom (Raymarine moderator). The forum is
closed; see the archived copy linked in the main README.
