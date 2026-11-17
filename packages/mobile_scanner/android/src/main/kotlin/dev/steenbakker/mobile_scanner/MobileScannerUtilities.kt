package dev.steenbakker.mobile_scanner

import android.graphics.ImageFormat
import android.graphics.Point
import android.graphics.Rect
import android.graphics.YuvImage
import android.media.Image
import dev.steenbakker.mobile_scanner.objects.BarcodeFormats
import java.io.ByteArrayOutputStream
import zxingcpp.BarcodeReader

fun Image.toByteArray(): ByteArray {
    val yBuffer = planes[0].buffer // Y
    val vuBuffer = planes[2].buffer // VU

    val ySize = yBuffer.remaining()
    val vuSize = vuBuffer.remaining()

    val nv21 = ByteArray(ySize + vuSize)

    yBuffer.get(nv21, 0, ySize)
    vuBuffer.get(nv21, ySize, vuSize)

    val yuvImage = YuvImage(nv21, ImageFormat.NV21, this.width, this.height, null)
    val out = ByteArrayOutputStream()
    yuvImage.compressToJpeg(Rect(0, 0, yuvImage.width, yuvImage.height), 50, out)
    return out.toByteArray()
}

/**
 * The four corners of a zxing-cpp result, clockwise from the top left, in the
 * coordinates of the upright image it was read from.
 */
val BarcodeReader.Result.cornerPoints: List<Point>
    get() = listOf(position.topLeft, position.topRight, position.bottomRight, position.bottomLeft)

/**
 * A zxing-cpp result as the Dart side reads a barcode (`Barcode.fromNative`).
 *
 * Cupola: zxing-cpp decodes the symbol and does not parse what it says, so
 * the structured fields (contact, Wi-Fi, URL and the rest) are absent and the
 * type is unknown (0). The text is both the raw and the display value.
 */
val BarcodeReader.Result.data: Map<String, Any?>
    get() {
        val corners = cornerPoints
        return mapOf(
            "corners" to corners.map { corner -> corner.data },
            "displayValue" to text,
            "format" to BarcodeFormats.fromZxing(format).intValue,
            "rawBytes" to bytes,
            "rawValue" to text,
            "size" to corners.bounds().size,
            "type" to 0,
        )
    }

private val Point.data: Map<String, Double>
    get() = mapOf("x" to x.toDouble(), "y" to y.toDouble())

private fun List<Point>.bounds(): Rect = Rect(
    minOf { it.x }, minOf { it.y }, maxOf { it.x }, maxOf { it.y },
)

private val Rect.size: Map<String, Any?>
    get() {
        // Rect.isValid can't be accessed for some reason, so just do the check manually.
        if (left <= right && top <= bottom) {
            return mapOf("width" to width().toDouble(), "height" to height().toDouble())
        }

        return emptyMap()
    }
