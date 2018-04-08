# BarcodeScanner
Basic Barcode Scanner Using Swift Vision Framework

Attached is a basic barcode scanner using Apple's Vision framework, derived from [lucatorella's BarcodeLocalizer](https://github.com/lucatorella/BarcodeLocalizer).

In experimenting with Vision, I've found it's a power hog, so you probably don't want to run it for an extended period of time.

To instantiate `BarcodeScannner`, you could call something like this from `YourViewController.swift`:

    let scannerVC = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "BarcodeScanner") as! BarcodeScanner
    scannerVC.delegate = self
    self.navigationController?.pushViewController(scannerVC, animated: true)

When BarcodeScanner's finds a barcode, it sets `detectedString: String`, which fires a delegate method to pass the value to the delegate ViewController and dismiss the scannner...from there, do what you please.

In `BarcodeScanner's setupVision` method, you can configure the barcodes it will detect.
