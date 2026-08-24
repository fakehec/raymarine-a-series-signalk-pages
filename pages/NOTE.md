# About the sample page

`Environment.qml` is a **sample** that shows the pattern (native DataItem cells +
custom HTTP `Text` tiles + an `XMLHttpRequest` poll).

It `import`s the DataItem **cell library** (`../Cells/Indicators/...`). That library
is **not included here** — it ships inside the YachtDevices RMDS package and belongs to
YachtDevices, so it is not mine to redistribute or relicense. Start from your own RMDS
package and drop pages like this one into its `Pages/` folder, then re-zip and import on
the MFD (see the main README, "Deploy & iterate").
