# Acloud

### Cloud rendering in D3D12 

### currently under development!

#### Features by now:

- raymarching into volume of 3d noise data
- inside each of the previous raymach iteration, using newly acquired sample position as new origin, do another raymarch toward sun for selfshadow approximation
- multi-layer perlin noise with worley noise
- level of detail noise
- compute shader generated P-W noise for approaching realistic coud shadpes:

![](DXSim/img/cloud.JPG)

- current raymarching effect

![](DXSim/img/g2.gif)

### Reference :
- [THE REAL-TIME VOLUMETRIC CLOUDSCAPES OF HORIZON ZERO DAWN](https://www.guerrilla-games.com/read/the-real-time-volumetric-cloudscapes-of-horizon-zero-dawn)
- [Physically Based Sky, Atmosphere and Cloud Rendering in Frostbite BY 
  S´ebastien Hillaire EA Frostbite](https://media.contentapi.ea.com/content/dam/eacom/frostbite/files/s2016-pbs-frostbite-sky-clouds-new.pdf)
