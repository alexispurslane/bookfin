{ pkgs }:
{
  model = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/4.1.0/eng.traineddata";
    sha256 = "7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2";
  };
  aar = pkgs.fetchurl {
    url = "https://jitpack.io/cz/adaptech/tesseract4android/tesseract4android/4.9.0/tesseract4android-4.9.0.aar";
    sha256 = "bce5d6413a1a5ae3d7240033fbbc851ba3217d0a08d9769400e17a077f42cb2a";
  };
  source = pkgs.fetchurl {
    url = "https://github.com/adaptech-cz/Tesseract4Android/archive/refs/tags/4.9.0.tar.gz";
    sha256 = "4569f9093d641d13188ba2dd36a74396661eaa3f9e44637ff1cac9a36076a20e";
  };
  modelLicense = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/4.1.0/LICENSE";
    sha256 = "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30";
  };
  hostEngine = pkgs.tesseract.override { enableLanguages = [ ]; };
}
