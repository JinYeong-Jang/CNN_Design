% 1) 데이터 준비 (0/1 필터는 네 코드 그대로)
% 1. 데이터 준비
% MNIST 훈련 데이터 불러오기
[XTrain, YTrain] = digitTrain4DArrayData;
% MNIST 테스트 데이터 불러오기
[XTest, YTest] = digitTest4DArrayData;

% 0과 1 레이블만 필터링
idxTrain = (YTrain == '0' | YTrain == '1');
XTrain = XTrain(:,:,:,idxTrain);
YTrain = YTrain(idxTrain);

idxTest = (YTest == '0' | YTest == '1');
XTest = XTest(:,:,:,idxTest);
YTest = YTest(idxTest);


% 라벨을 0/1(single)로
YTrain = single(YTrain == '1');
YTest  = single(YTest  == '1');

% 2) dlarray로 포맷 지정 (★중요)
XTrain = dlarray(XTrain, 'SSCB');           % 28x28x1xN
XTest  = dlarray(XTest , 'SSCB');           % 28x28x1xN

YTrain = dlarray(reshape(YTrain,1,[]), 'CB'); % 1xN
YTest  = dlarray(reshape(YTest ,1,[]), 'CB'); % 1xN

% 3) 모델 (시그모이드 포함)
layers = [
    imageInputLayer([28 28 1], 'Name','input_layer')
    convolution2dLayer(3,16,'Padding','same','Name','conv1')
    reluLayer('Name','relu1')
    maxPooling2dLayer(2,'Stride',2,'Name','maxpool1')
    flattenLayer('Name','flatten')
    fullyConnectedLayer(1,'Name','dense1')
    sigmoidLayer('Name','sigmoid')   % 확률로 출력
];

options = trainingOptions('adam', ...
    'InitialLearnRate',1e-3, ...
    'MaxEpochs',10, ...
    'MiniBatchSize',128, ...
    'ValidationData',{XTest, YTest}, ...  % dlarray도 OK
    'Shuffle','every-epoch', ...
    'Plots','training-progress');

% 4) 학습 
net = trainnet(XTrain, YTrain, layers, 'binary-crossentropy', options);

% 5) 평가
YScores = predict(net, XTest);          % 형상: 1xN (CB)
YScores = extractdata(YScores);         % double/single로
YPred = YScores > 0.5;                  % 0/1 예측

YTrue = extractdata(YTest);             % 1xN
acc = mean(YPred == (YTrue > 0.5));
fprintf('정확도: %.4f%%\n', acc*100);

lg = layerGraph(net);
lg = removeLayers(lg,'sigmoid');     
net_logits = dlnetwork(lg);
save('mnist_net_logits.mat','net_logits');