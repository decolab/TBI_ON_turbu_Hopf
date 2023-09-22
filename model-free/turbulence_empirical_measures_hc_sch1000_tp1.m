%% Turbulence all empirical measurements original
% Analyze turbulence from the TBI dataset in OpenNeuro: <https://openneuro.org/datasets/ds000220/versions/1.0.0/file-display/dataset_description.json 
% https://openneuro.org/datasets/ds000220/versions/1.0.0/file-display/dataset_description.json>

% Load inputs
clear all
cd('/Volumes/LASA/TBI_OpenNeuro/TBI_openneuro/timeseries/inputs_sch1000/');
load('tseries_openneuro_controls_tp1_sch1000.mat')               % Denoised time-series
load ('RSN7vector.mat');                                         % Labels for the 7 RSN (Yeo, 2011)
load('SchaeferCOG.mat');                                         % Center of gravity coordinates in the Schaefer parcellation
labels= Yeo7vector;
%1: VIS; 2:SM, 3:DAT, 4:VTA; 5:LIM; 6:CON; 7:DMN
addpath('/Volumes/LASA/TBI_OpenNeuro/Shared_code/Turbulence/TBI_turbulence_current_code/')
addpath('/Volumes/LASA/TBI_OpenNeuro/Shared_code/Turbulence/TBI_turbulence_current_code/helper functions')

% Set Parameters
cond=1;                                     % Number of sessions
xs=tseries(:,cond);                         % Time-series
NSUB=size(find(~cellfun(@isempty,xs)),1);   % Total subjects in each group
TR=2;                                       % Repetition Time (seconds), equivalent to the sampling rate
Tmax=144;                                   % Number of resting-state volumes
NPARCELLS=1000;                             % Number of nodes in Schaefer's parcellation
NR=400;                               
NRini=20;
NRfin=80;

LAMBDA=[0.27 0.24 0.21 0.18 0.15 0.12 0.09 0.06 0.03 0.01]; % Range of lambda values in 0.03 steps
NLAMBDA=length(LAMBDA);

% Bandpass filter settings
fnq=1/(2*TR);                 % Nyquist frequency
flp = 0.008;                  % Lowpass frequency of filter (Hz)
fhi = 0.08;                   % Lowpass frequency of filter (Hz)
Wn=[flp/fnq fhi/fnq];         % Butterworth bandpass non-dimensional frequency
k=2;                          % 2nd order butterworth filter
[bfilt,afilt]=butter(k,Wn);   % Construct the filter

% Calculates array of distance between the nodes' centroids
for i=1:NPARCELLS
    for j=1:NPARCELLS
        rr(i,j)=norm(SchaeferCOG(i,:)-SchaeferCOG(j,:)); % Returns the Euclidean norm of vector v or Euclidean length.
    end
end
range=max(max(rr));
delta=range/NR;

for i=1:NR
    xrange(i)=delta/2+delta*(i-1);
end

% Calculates array of exponential decay between nodes for each lambda
C1=zeros(NLAMBDA,NPARCELLS,NPARCELLS);
ilam=1;
for lambda=LAMBDA
    for i=1:NPARCELLS
        for j=1:NPARCELLS
            C1(ilam,i,j)=exp(-lambda*rr(i,j));
        end
    end
    ilam=ilam+1;
end

% Preallocate variables

%intermediate variables
signal_filt=zeros(NPARCELLS,Tmax);
Phases=zeros(NPARCELLS,Tmax);
entropy1=zeros(NLAMBDA,NPARCELLS,Tmax);
fcr=zeros(NLAMBDA,NSUB);
fclam=zeros(NLAMBDA,NPARCELLS,NPARCELLS);

%outputs per subject
Turbulence_sub=zeros(NLAMBDA,NSUB); % Amplitude turbulence
TransferLambda_sub=zeros(NLAMBDA,NSUB); % Information cascade flow
InformationCascade_sub=zeros(1,NSUB); % Information cascade
Transfer_sub=zeros(1,NSUB); %Information transfer

%---------------------------------------------------------------------------------------------------------------------
% Compute observables 

for sub=1:NSUB
    NPARCELLS=1000;                             
    ts=tseries{sub,cond};
    clear Phases Xanalytic signal_filt Phases_surrogate

    % Hilbert transform to calculate the instantaneous phases per node
    for seed=1:NPARCELLS
        ts(seed,:)=detrend(ts(seed,:)-mean(ts(seed,:)));                 % Detrend the time-series
        signal_filt(seed,:) =filtfilt(bfilt,afilt,ts(seed,:));           % Zero phase filtering with 2nd-order butterworth filter      
        Xanalytic = hilbert(demean(signal_filt(seed,:)));                % Get the analytic signal
        Phases(seed,:) = angle(Xanalytic);                               % Get the phases from the analytic signal
        %Visualization
%         figure,plot(ts(seed,:),'r'), hold on, plot(signal_filt(seed,:),'b'), title('Signal filtering'), legend('signal','signal filtered')
%         figure,plot(real(Xanalytic),'r'), hold on, plot(imag(Xanalytic),'b'), title('Hilbert transform'), legend('real','imag')
%         figure,plot3(1:Tmax, real(Xanalytic),imag(Xanalytic)), title('Hilbert transform 3d')
%         xlabel('Time(ms)'),ylabel('Real'),zlabel('Imag')
%         axis tight
%         rotate3d
    end

    % Calculate Kuramoto LOCAL order parameter for all nodes and turbulence
    % per node
    for i=1:NPARCELLS
        for ilam=1:NLAMBDA
            C1lam=squeeze(C1(ilam,:,:));
            sumphases=nansum(repmat(C1lam(i,:)',1,Tmax).*complex(cos(Phases),sin(Phases)))/nansum(C1lam(i,:));
            entropy1(ilam,i,:)=abs(sumphases); % Kuramoto local order parameter
            Turbulence_node_sub(ilam,i,sub)=nanstd(entropy1(ilam,i,:)); %Amplitude turbulence (std of Kuramoto local order parameter per node across timepoints)
        end
    end
    
    % Calculate amplitude turbulence for all nodes
    for ilam=1:NLAMBDA
        Turbulence_global_sub(ilam,sub)=nanstd(squeeze(entropy1(ilam,:))); % Amplitude turbulence (std of Kuramoto local order parameter across nodes and timepoints)
    end
    
    % Calculate Kuramoto global order parameter and metastability for all nodes
    gKoP(sub)=nanmean(abs(sum(complex(cos(Phases(:,:)),sin(Phases(:,:))),1))/NPARCELLS);    % Global Kuramoto parameter (synchronization) for all nodes
    Meta(sub) = nanstd(abs(sum(complex(cos(Phases(:,:)),sin(Phases(:,:))),1))/NPARCELLS);   % Global metastability for all nodes

    % Calculate amplitude turbulence, Kuramoto global order parameter and
    % metastability for the 7 RSNs
    for ii=1:7
        indx_rsn=find(labels(:,1)==ii);
        NPARCELLS=size(indx_rsn,1);
        clear entropy
        for ilam=1:NLAMBDA
            entropy(ilam,:,:) = entropy1(ilam,indx_rsn,:); %Kuramoto module
            TurbulenceRSN_sub(ilam,sub,ii)=nanstd(squeeze(entropy(ilam,:))); % Amplitude turbulence for each network (based on Kuramoto module for all 1000 nodes but STD from the nodes)
        end
        gKoPRSN(sub,ii)=nanmean(abs(sum(complex(cos(Phases(indx_rsn,:)),sin(Phases(indx_rsn,:))),1))/NPARCELLS); %global Kuramoto parameter (synchronization) for each network
        MetaRSN(sub,ii) = nanstd(abs(sum(complex(cos(Phases(indx_rsn,:)),sin(Phases(indx_rsn,:))),1))/NPARCELLS); %global metastability for each network

    end

    % Calculate info cascade flow and info cascade 
    for ilam=1:NLAMBDA-1
        [cc pp]=corr(squeeze(entropy1(ilam+1,:,2:end))',squeeze(entropy1(ilam,:,1:end-1))');
        TransferLambda_sub(ilam+1,sub)=nanmean(abs(cc(find(pp(:)<0.05)))); %info flow
    end

    InformationCascade_sub(sub)=nanmean(TransferLambda_sub(2:NLAMBDA,sub),1); % info cascade

% Calculate info transfer
    clear fclam
    for ilam=1:NLAMBDA
        fclam(ilam,:,:)=corrcoef(squeeze(entropy1(ilam,:,:))');
        %Visualization
        %figure, imagesc(fclam(ilam,:,:)), title('Correlation coefficient Kuramoto local order parameter')
    end
  

    for lam=1:NLAMBDA
        numind=zeros(1,NR);
        fcra=zeros(1,NR);
        for i=1:NPARCELLS
            for j=1:NPARCELLS
                r=rr(i,j);
                index=floor(r/delta)+1;
                if index==NR+1
                    index=NR;
                end
                mcc=fclam(lam,i,j);
                if ~isnan(mcc)
                    fcra(index)=fcra(index)+mcc;
                    numind(index)=numind(index)+1;
                end
            end
        end
        %%  Calculate the slope 
        grandcorrfcn=fcra./numind;
        clear xcoor;
        clear ycoor;
        nn=1;
        indxx = find(~isnan(grandcorrfcn));
        indices = indxx(indxx>NRini & indxx<NRfin);
        for k=1:length(indices)
            if grandcorrfcn(k)>0
                xcoor(nn)=log(xrange(k));
                ycoor(nn)=log(grandcorrfcn(k)/grandcorrfcn(indices(1)));
                nn=nn+1;
            end
        end
        %least square non-linear curve fitting
        linfunc = @(A, x)(A(1)*x+A(2)); %fitting function
        options=optimset('MaxFunEvals',10000,'MaxIter',1000,'Display','final'); %Maximum number of function evaluation, maximum number of iterations, 
        A0=[-1 1]; %initial parameter
        lb=[-4 -10]; %lower bound
        ub=[4 10]; %upper bound
        [Afit Residual]= lsqcurvefit(linfunc,A0,xcoor,ycoor,lb, ub, options);
        Transfer_sub(lam,sub)=abs(Afit(1)); %slope

    end
end

cd ('/Volumes/LASA/TBI_OpenNeuro/TBI_openneuro/timeseries/outputs/Turbulence_20_06_2023/')
save (sprintf('turbu_all_measurements_openneuro_controls_con%d.mat',cond), 'LAMBDA','TurbulenceRSN_sub','Turbulence_global_sub', 'Transfer_sub', 'InformationCascade_sub', 'TransferLambda_sub','gKoPRSN','MetaRSN','gKoP','Meta');
save (sprintf('turbu_by_node_openneuro_controls_con%d.mat',cond), 'Turbulence_node_sub');