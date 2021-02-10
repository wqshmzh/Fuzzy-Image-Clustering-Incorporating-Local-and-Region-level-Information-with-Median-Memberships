function region_level = region_level_information(f, l, S, g, sigma)
% Function for region-level information calculation
% Inputs:
% f - Input image
% l - Side length of block
% S - Side length of region
% g - Attenuation of exponential function in Eqs. (4)-(5)
% sigma - Standard deviation of Gaussian function
%----------------------------------

[m, n, depth] = size(f);
f = double(f);
mask = fspecial('gaussian', [l l], sigma);
region_level = zeros(m, n, depth);
for i = 1 : depth
    half_side = floor(S / 2);
    whole_region = padarray(f(:, :, i), [half_side, half_side], 'symmetric');
    B = 0;
    g2 = g * g;
    for t1 = -half_side : half_side
        for t2 = -half_side : half_side
            if(t1 == 0 && t2 == 0)
                continue;
            end
            SqDist2 = (whole_region(1 + half_side : end - half_side, 1 + half_side : end - half_side) - ...
                               whole_region(1 + half_side + t1 : end - half_side + t1, 1 + half_side + t2 : end - half_side + t2)) .^ 2;
            SqDist2 = imfilter(SqDist2, mask, 'symmetric');
            SqDist2 = SqDist2 / l ^ 2;
            w = exp( - SqDist2 ./ g2);
            sub_region = whole_region(1 + half_side + t1 : end - half_side + t1, 1 + half_side + t2 : end - half_side + t2);
            region_level(:, :, i) = region_level(:, :, i) + w .* sub_region;
            B = B + w;
        end
    end
    region_level(:, :, i) = region_level(:, :, i) ./ B;
end
end
