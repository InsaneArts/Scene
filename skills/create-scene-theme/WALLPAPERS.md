# Wallpapers

## What belongs

- **Colors**: the wallpaper's main colors come from the palette.
- **Light**: a dark look gets a dark image, and a light look a light one.
- **Composition**: a calm middle, because windows sit there. Detail goes to the edges or a low horizon, and the top strip stays quiet for the menu bar.
- **Clean**: no text, letters, logos, watermarks, signatures, interface, brands, flags, emblems, or faces of real people. A generic object that looks like a famous product is a brand too.
- **Three that differ**: for example a scene, an abstract, and a pattern. Three versions of one picture make one wallpaper.

## Routes

**The person's own images.** Ask which files, and check each one against "What belongs". Put their name in `attribution`.

**Found images.** The theme folder is shared publicly, so take only images that anyone may share: public domain, CC0, or CC BY. The image's own page says which; put that page in `source`.

| Source | `attribution` |
|---|---|
| NASA, JPL, NOAA, USGS | The agency, for example "NASA", or "Courtesy NASA/JPL-Caltech" as JPL asks |
| Museum open access (the Met, Art Institute of Chicago, Cleveland, National Gallery of Art, Rijksmuseum, Smithsonian CC0 items) | Artist, title, date, museum |
| Wikimedia Commons files marked CC0 or public domain | Author, as on the file page |
| ESA/Hubble, ESA/Webb | The credit line exactly as published |

NASA's image search needs no key: `https://images-api.nasa.gov/search?q=<words>&media_type=image`, then `https://images-api.nasa.gov/asset/<nasa_id>` lists the files; take the `~orig.jpg`. Leave out images with identifiable people, logos, insignia, or a credit that names someone other than the agency or museum. Unsplash, Pexels, and Pixabay do not qualify: their terms forbid wallpaper apps.

**Generated images**, only with an image tool you have. Describe one concrete picture with its light and framing, name the palette's main colors, and ask for no text, logos, or people. Look at the result at full size, including walls and screens where small logos hide, and make it again when anything from "Clean" shows. Put "Generated with <tool>" in `attribution`.

## Preparing the files

`sips` ships with macOS.

```sh
sips -g pixelWidth -g pixelHeight image.jpg                       # the size
sips -s format jpeg -s formatOptions 90 image.webp --out dark-1.jpg  # to JPEG from WebP, TIFF, or others
sips -Z 3840 big.jpg --out dark-1.jpg                             # longest side to 3840 px
```

Name the files `images/dark-1.jpg` … `images/light-3.jpg`. Keep each under 20 MB and all of them under 39 MB together; a 3840 px JPEG at quality 85 to 90 is about 1 to 4 MB. JPEG or PNG shows in the repository's README on GitHub; HEIC shows in Scene but not in most browsers.
