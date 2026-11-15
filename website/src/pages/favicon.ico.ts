import type { APIRoute } from 'astro';
import { brandSvg } from '../lib/repo';
import { png } from '../lib/og';

// Browsers and crawlers that ignore the page's <link rel="icon"> ask for
// /favicon.ico by name. An ICO may carry PNGs as they are, so it holds the
// launcher at 16, 32 and 48 px.
export const GET: APIRoute = () => {
  const images = [16, 32, 48].map((size) => ({ size, data: png(brandSvg('cupola_launcher'), size) }));
  const header = Buffer.alloc(6 + 16 * images.length);
  header.writeUInt16LE(0, 0);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(images.length, 4);
  let offset = header.length;
  images.forEach(({ size, data }, i) => {
    const entry = 6 + 16 * i;
    header.writeUInt8(size, entry);
    header.writeUInt8(size, entry + 1);
    header.writeUInt16LE(1, entry + 4);
    header.writeUInt16LE(32, entry + 6);
    header.writeUInt32LE(data.length, entry + 8);
    header.writeUInt32LE(offset, entry + 12);
    offset += data.length;
  });
  return new Response(new Uint8Array(Buffer.concat([header, ...images.map((x) => x.data)])), {
    headers: { 'Content-Type': 'image/x-icon' },
  });
};
