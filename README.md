#    P5StrikersFix-AI-Fork

[!WARNING]

This solution did not end up working. Text boxes still had a very aliased apperence. My solution ended up being to try and optimize the Reshade NN-Shaders.

This is not a perfect solution and still >produces some artifacts, but does look better than stock. The SMAA in the Luma-Framework modficiation does not seem to impact the HUD.

For code perspective, it will be archived.


This is a fork of [Lyall's P5StrikersFix](https://codeberg.org/Lyall/P5StrikersFix) modification that tries and separate the HUD and game resolution scaling.

The idea is you can play the game at 70% of 1080P with upscaling while having a sharp 4K HUD.

## Known Issues
Please report any issues you see.
This list will contain bugs which may or may not be fixed.

- Cutscene letterboxing looks bad at <16:9. I'd recommend disabling the cutscene letterboxing in **P5StrikersFix.ini**.

## Credits
[Ultimate ASI Loader](https://github.com/ThirteenAG/Ultimate-ASI-Loader) for ASI loading. <br />
[inipp](https://github.com/mcmtroffaes/inipp) for ini reading. <br />
[spdlog](https://github.com/gabime/spdlog) for logging. <br />
[safetyhook](https://github.com/cursey/safetyhook) for hooking.
