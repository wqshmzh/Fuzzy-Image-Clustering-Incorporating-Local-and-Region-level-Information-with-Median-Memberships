%% BEST RUN WITH MATLAB R2018b!
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Fuzzy Image Clustering Incorporating Local and Region-level Information with Median Memberships
% Applied Soft Computing Journal
% This code was written by Qingsheng Wang in December, 2020.
% At Lanzhou Jiaotong University, Lanzhou, China
%
% GPU is recomended.
% To use GPU in MATLAB R2018b, Nvidia graphic card with CUDA 9.1+ MUST be installed.
% For other MATLAB versions, please refer to related documents to install CUDA with correct version.
%
% Detailed membership degrees in a randomly collected 5x5 local area can be seen in the following two matrices:
% Cluster_1 - U_cluster1_local_5x5
% Cluster_2 - U_cluster2_local_5x5
% After running this code, you can find them in the MATLAB Working Space.
%
% Basically, you can run this code SEVERAL times to acquire the most desired result.
% It is welcomed to change the following parameters as you like to see what gonna happen.
%
% Inputs:
% density - Mixed noise density
% error - Minimum absolute difference between ath J and (a-1)th J
% cluster_num - Number of clusters
% max_iter - Max iterations
% gamma - Constraint for KL information
% k - Control factor in Eq. (21)
% d - Side length of median filter for membership degrees
% ==============Parameters for region-level information================
% l - Side length of block
% S - Side length of region
% g - Attenuation of exponential function in Eqs. (4)-(5)
% sigma - Gaussian standard deviation
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Initialization
clear all;
close all;
flag = gpuDeviceCount; % Number of callable GPUs.
if flag 
    fprintf("You have at least one GPU installed.\n");
end
%% Input image
f_uint8 = imread('sy2.bmp'); % f_uint8 restores input image as uint8.
f = double(f_uint8);
%% Parameters
density = 0.2;
error = 0.01;
cluster_num = 4;
max_iter = 200;
gamma = 0.4;
k = 50;
d = 5;
% Parameters for region-level information
l = 9;
S = 15;
g = 5; 
sigma = 4;
%% Construct mixed noise
f = f / 255;
f = imnoise(f, 'gaussian', 0, density);
f = imnoise(f, 'salt & pepper', density);
f = imnoise(f, 'speckle', density);
figure, imshow(f);
title('Original image I');
f = f * 255;
%% Acquire region_level information
if flag
    f = gpuArray(f);
end
f_region_information = region_level_information(flag, f, l, S, g, sigma);
figure, imshow(uint8(f_region_information));
title('Image of region level-information I_R');
%% Nomalization
f_region_information = f_region_information / 255;
f = f / 255;
%% Mean template of region-level information
mask = fspecial('average', 7);
f_local = imfilter(f_region_information, mask, 'symmetric');
if flag
    f_local = gpuArray(f_local);
end
%% Calculate adaptive weights ��_jz (denoted as xi in this file) in Eq. (15)
[row, col, depth] = size(f);
n = row * col;
if flag
    xi = gpuArray(zeros(row, col, depth));
else
    xi = zeros(row, col, depth);
end
phi = (255 * (f_local - f_region_information)) .^ 2; % Eq. (13)
phi_padded = padarray(phi, [1 1], 'symmetric');
phi_std = stdfilt(phi, ones(3)) + eps; % ��_jz
for i = -1 : 1
    for j = -1 : 1
        xi = xi + (exp(abs(phi_padded(i + 1 + 1 : end + i - 1, j + 1 + 1 : end + j - 1, :) - phi) ./ phi_std) - 1); % Eq. (14)
    end
end
min_xi = min(min(min(xi)));
max_xi = max(max(max(xi)));
xi =(xi - min_xi)./(max_xi-min_xi); % Eq. (15)
xi = repmat(reshape(xi, n, 1, depth), [1 cluster_num 1]);
%% Calculate Eq. (21)
difference = k * exp(stdfilt(f, ones(3)) - stdfilt(f_region_information, ones(3))) + eps;
difference = repmat(reshape(difference, row * col, 1, depth), [1 cluster_num 1]);
%% Size reshaping
f = repmat(reshape(f, n, 1, depth), [1 cluster_num 1]);
f_region_information = repmat(reshape(f_region_information, n, 1, depth), [1 cluster_num 1]);
f_local = repmat(reshape(f_local, n, 1, depth), [1 cluster_num 1]);
%% Initialization of clustering
% Membership degrees
U =rand(n, cluster_num);
% Eq. (22)
alpha = 1 ./ difference;
% Eq. (23)
beta = difference;
% Objective function
J = zeros(max_iter, 1);
% 5x5 membership degrees local area
U_cluster1_local_5x5 = zeros(5, 5, max_iter); % cluster_1
U_cluster2_local_5x5 = zeros(5, 5, max_iter); % cluster_2
% Transmit to GPU
if flag
    U = gpuArray(U);
    J = gpuArray(J);
    U_cluster1_local_5x5 = gpuArray(U_cluster1_local_5x5);
    U_cluster2_local_5x5 = gpuArray(U_cluster2_local_5x5);
end
% Process U
U_col_sum = sum(U, 2);
U = U ./ U_col_sum;
%% Fuzzy clustering
for iter = 1 : max_iter
    % Locally median membership degrees Eq. (18)
    half_d = floor(d  / 2);
    U = reshape(U, row, col, cluster_num);
    pi = padarray(zeros(row, col, cluster_num), [half_d half_d], 'symmetric');
    if flag
        pi = gpuArray(pi);
    end
    U = padarray(U, [half_d half_d], 'symmetric');
    for i = 1 : cluster_num
        % If medfilt2 function is called by GPU, edge padding method is not able to be specified by user. 
        % So I padded edges of U before this loop.
        pi(:, :, i) = medfilt2(gather(U(:, :, i)), [d, d]);
    end
    U = U(half_d + 1 : end - half_d, half_d + 1 : end - half_d, :);
    pi = pi(half_d + 1 : end - half_d, half_d + 1 : end - half_d, :);
    U = reshape(U, row * col, cluster_num);
    pi = reshape(pi, row * col, cluster_num);
    % Update cluster centers by Eq. (32)
    U = repmat(U, [1 1 depth]);
    center = sum(alpha .* U .* f + beta .* U .* (xi .* f_local + (1 - xi) .* f_region_information)) ./ sum((alpha + beta) .* U);
    % Compute Euclidean distance
    center_rep = repmat(center, [n 1 1]);
    dist_a = mean(alpha .* (f - center_rep) .^2, 3);
    dist_b = mean(beta .* (xi .* (f_local - center_rep) .^ 2 + (1 - xi) .* (f_region_information - center_rep) .^ 2), 3);
    dist = dist_a + dist_b;
    % Update membership degrees by Eq. (31)
    U_numerator = pi .* exp(-(pi .* gamma + dist) ./ gamma) + eps;
    U = U_numerator ./ sum(U_numerator, 2);
    % Check local membership degrees
    U_reshape1 = reshape(U(:, 1), row, col);
    U_reshape2 = reshape(U(:, 2), row, col);
    U_cluster1_local_5x5(:, :, iter) = U_reshape1(60 : 64, 20 : 24); % 60 64 20 24 are collected randomly
    U_cluster2_local_5x5(:, :, iter) = U_reshape2(60 : 64, 20 : 24);
    % Update objective function by Eq. (25)
    J(iter) = sum(sum(dist .* U + gamma .* U .* log(U ./ pi)));
    fprintf('Iter %d\n', iter);
    % Iteration stopping condition
    if iter > 1 && abs(J(iter - 1) - J(iter)) <= error
        fprintf('Objective function is converged.\n');
        break;
    end
    if iter > 1 && iter == max_iter
        fprintf('Objective function is not converged. Max iteration reached.\n');
        break;
    end
end
center = uint8(gather(squeeze(center * 255)));
%% Output segmentation result
[~, cluster_indice] = max(gather(U), [], 2);
% To see how clear the membership partition.
Vpc = sum(sum(gather(U) .^ 2, 'all')) / n * 100;
Vpe = -sum(sum(gather(U) .* log(gather(U)))) / n * 100;
fprintf('Fuzzy partition coefficient Vpc = %.2f%%\n', Vpc);
fprintf('Fuzzy partition entropy Vpe = %.2f%%\n', Vpe);
% Visualize all labels
FCM_result = Label_image(f_uint8, reshape(cluster_indice, row, col));
figure, imshow(FCM_result);
title('Segmentation result');
% Visualize objective function
J=gather(J);
figure,plot(J(1: iter));
title('Objective function J');