package dev.steenbakker.mobile_scanner.objects

import zxingcpp.BarcodeReader.Format

/**
 * The barcode formats the Dart side names, by the integer it sends and reads
 * back (`BarcodeFormat.rawValue`).
 *
 * Cupola: the integers are the ones the plugin has always used, so the Dart
 * side is unchanged; each format also names the zxing-cpp format that reads
 * it.
 */
enum class BarcodeFormats(val intValue: Int, val zxing: Format?) {
    UNKNOWN(-1, null),
    ALL_FORMATS(0, null),
    CODE_128(1, Format.CODE_128),
    CODE_39(2, Format.CODE_39),
    CODE_93(4, Format.CODE_93),
    CODABAR(8, Format.CODABAR),
    DATA_MATRIX(16, Format.DATA_MATRIX),
    EAN_13(32, Format.EAN_13),
    EAN_8(64, Format.EAN_8),
    ITF(128, Format.ITF),
    QR_CODE(256, Format.QR_CODE),
    UPC_A(512, Format.UPC_A),
    UPC_E(1024, Format.UPC_E),
    PDF417(2048, Format.PDF_417),
    AZTEC(4096, Format.AZTEC);

    companion object {
        fun fromRawValue(rawValue: Int): BarcodeFormats {
            return when(rawValue) {
                -1 -> UNKNOWN
                0 -> ALL_FORMATS
                1 -> CODE_128
                2 -> CODE_39
                4 -> CODE_93
                8 -> CODABAR
                16 -> DATA_MATRIX
                32 -> EAN_13
                64 -> EAN_8
                126, 127, 128 -> ITF
                256 -> QR_CODE
                512 -> UPC_A
                1024 -> UPC_E
                2048 -> PDF417
                4096 -> AZTEC
                else -> UNKNOWN
            }
        }

        /**
         * The format a zxing-cpp result reports, as the Dart side names it.
         * zxing-cpp splits some formats into variants (QR model 1 and 2,
         * Code 39 standard and extended), which read as their family here.
         */
        fun fromZxing(format: Format): BarcodeFormats {
            return when(format) {
                Format.CODE_128 -> CODE_128
                Format.CODE_39, Format.CODE_39_STD, Format.CODE_39_EXT -> CODE_39
                Format.CODE_93 -> CODE_93
                Format.CODABAR -> CODABAR
                Format.DATA_MATRIX -> DATA_MATRIX
                Format.EAN_13 -> EAN_13
                Format.EAN_8 -> EAN_8
                Format.ITF, Format.ITF_14 -> ITF
                Format.QR_CODE, Format.QR_CODE_MODEL_1, Format.QR_CODE_MODEL_2 -> QR_CODE
                Format.UPC_A -> UPC_A
                Format.UPC_E -> UPC_E
                Format.PDF_417, Format.COMPACT_PDF_417 -> PDF417
                Format.AZTEC, Format.AZTEC_CODE -> AZTEC
                else -> UNKNOWN
            }
        }
    }
}
