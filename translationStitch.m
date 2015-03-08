

%% Force homographies to be translation only
for i = 1: length(HomographyMatrix)
    HomographyMatrix{i}(:, 1:2) = [1 0; 0 1; 0 0];
    
    % Translation from i to i + 1
    translations(1:2, i + 1) = HomographyMatrix{i}(1:2, end);
end

% Force tail images to be at the same height if inputs are 360 deg
% NOTE: this part isn't well tested.
if exist('is360', 'var') && is360
    disp(translations);
    disp(translations(2, end))
    translations(2, 1:end-1) = translations(2, 1:end-1) - ...
        linspace(0, translations(2, end), size(translations, 2) - 1);
    disp(translations);
end

% Get offset of images with respect to panorama frame
global_offsets = cumsum(-translations(:, 1:end - 1), 2);

% Make sure all translations are positive
for dim = 1: 2
    global_offsets(dim, :) = global_offsets(dim, :) - min(global_offsets(dim, :));
end

% Translate
for i = 1 : numImages
    offset = global_offsets(:, i)';
    imtranslateds{i} = imtranslate(cylindricalImage{i}, offset, 'OutputView', 'full');
end

%% Erode images so that we don't get black artifacts at the border after stitching
for i = 1 : numImages    
    % Mask that's 1 at the pixels we allow to survive after cropping
    % We need to pad array with 1 pixel of zeros otherwise positive values
    % at the border will not be eroded.
    maskBefore = padarray(rgb2gray(imtranslateds{i}) > 0, [1  1]);
    maskAfter = imerode(maskBefore, strel('square', 3));
    maskAfter = maskAfter(2:end-1, 2:end-1);  % remove pads that we added
    
    % Zero everything outside mask
    imtranslateds{i}(~repmat(maskAfter, [1, 1, 3])) = 0;

end


%%
% Add black pixels to bottom and right of each translated so that they're
% all the same size
for i = 1 : numImages
    sizes(i, :) = size(imtranslateds{i});
end
maxHeight = max(sizes(:, 1));
maxWidth = max(sizes(:, 2));
for i = 1 : numImages
    currSize = size(imtranslateds{i});
    imtranslateds{i} = padarray(imtranslateds{i}, [maxHeight maxWidth] - currSize(1:2), ...
        0, 'post');
end

%% Equalize image exposures to reduce sharp changes in brightness when stitching

% Find the average brightness of each image compared to some global
% standard
ratios = 1;
for i = 1 : numImages - 1
   im1 = rgb2gray(imtranslateds{i});
   im2 = rgb2gray(imtranslateds{i + 1});
   overlap = im1 > 0 & im2 > 0;
   ratio = sum(im2(overlap)) / sum(im1(overlap));
   ratios(i + 1) = ratio;
end
global_exposures = cumprod(ratios);  % low value means image too dark
 
% Set median exposure to be 1 so that average exposure isn't too bright or
% dark
global_exposures = global_exposures / median(global_exposures);
% global_exposures = global_exposures / min(global_exposures);
 
% Equalize exposure individually
for i = 1 : numImages
      % Average ratio with 1 so that we don't make the compensation too
      % extreme. Results seem better if we don't go all out with
      % global_exposures(i)
    divisor = (global_exposures(i) + 1) / 2;
    imtranslateds{i} = uint8(double(imtranslateds{i}) / divisor);
end
 
%% Perform stitching by alpha blending input images 1 by 1 to panorama
imPanorama = imtranslateds{1};
for i = 2 : numImages
    
    imtranslated = imtranslateds{i};
    imPanorama = alpha_blend(imPanorama, imtranslated);
end

% Display translated images in a single figure
stackImTranslateds = zeros([size(imtranslateds{1}), numImages], 'uint8');
for i = 1 : numImages
    stackImTranslateds(:, :, :, i) = imtranslateds{i};
end
figure('name', 'translated images');montage(stackImTranslateds);

%% Crop panorama by hill-climbing

imPanoramaCropped = removeBlackPixels(imPanorama);

figure('name', 'Stitched image'); imshow(imPanorama);
figure('name', 'Stitched > cropped'); imshow(imPanoramaCropped);