// TỆP SINH TỰ ĐỘNG — đừng sửa tay.
//
// Tần suất âm tiết tiếng Việt, dẫn xuất từ danh sách `content/2018/vi/vi_50k.txt` của dự án FrequencyWords
// (Hermit Dave, https://github.com/hermitdave/FrequencyWords), đếm trên kho phụ đề OpenSubtitles 2018.
// Dữ liệu gốc theo giấy phép CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/).
// Thay đổi so với bản gốc: chỉ giữ các mục là âm tiết tiếng Việt đúng chính tả (theo `Syl.isValid`), gộp các
// cách viết cùng một âm tiết ("hoà"/"hòa") về một khoá, và bỏ mục dưới 100 lần.
//
// Sinh lại: tải `vi_50k.txt`, chạy `swift run vnkey-tool syllables <tệp> 100`, rồi xếp kết quả vào chuỗi bên dưới.
// Mỗi mục là "khoá số_lần"; khoá = chữ thường đã bỏ thanh + số của thanh (xem `Charset.syllableKey`).

extension CommonWords {
    static let entryCount = 3320
    static let data = """
        tôi0 711535 không0 668048 la2 486551 co1 477265 anh0 469245 ta0 342219 cua3 266574 đi0 254203 đa4 252899
        đo1 247903 se4 246292 chung1 242236 gi2 241762 môt5 238831 đươc5 235376 va2 226759 cô0 214453 lam2 211016
        phai3 210120 rôi2 203200 ngươi2 200740 nay2 195910 cho0 185833 em0 177577 đây0 174127 con0 168380 sao0 162224
        biêt1 159361 noi1 158706 no1 157631 thê3 155889 ông0 155744 vơi1 147044 câu5 145323 thê1 140460 lai5 136874
        vây5 135209 ra0 133754 đê3 124238 nao2 124150 ây1 121010 cai1 120229 đang0 112941 muôn1 110604 ma2 108399
        trong0 108108 như0 105810 nhưng0 104672 nhưng4 98367 đên1 98021 khi0 96056 đâu0 95631 chuyên5 95137 chi3 91947
        ca3 89175 vê2 88378 thi2 87639 ho5 86851 giơ2 84390 thây1 83284 con2 82930 thôi0 82257 cung4 81072 vao2 78661
        cac1 77561 bi5 76062 nghi4 75696 đây1 74693 thât5 74212 ai0 72950 hăn1 72489 nêu1 72302 minh2 71757 viêc5 67862
        nưa4 67200 rât1 67014 vi2 66750 cân2 66095 chư1 63083 a2 63024 điêu2 62637 sư5 59293 tơi1 57132 thư1 55496
        nha2 54977 xin0 54951 chưa0 54331 đung1 54175 tư2 53715 lên0 53245 me5 53028 nghe0 51467 moi5 51104 ban5 50850
        hơn0 50810 tơ1 50054 may2 49614 chêt1 49472 nên0 49046 đâu2 48553 ơn0 47895 đưng2 47695 tim2 47663 tôt1 47009
        hay4 43506 tin0 43073 qua1 42845 nhiêu2 42608 trươc1 42292 cam3 42134 ba2 42036 y1 41826 nhât1 40441 hay0 40080
        bô1 40013 công0 39715 tao0 39537 tât1 39525 bao0 38062 lôi4 38022 trên0 37958 tên0 37934 tai5 37547 thanh2 36506
        ngay2 36131 khac1 35964 chau1 35959 sau0 35762 chăc1 35097 xem0 35017 theo0 34891 găp5 34786 băt1 34736
        cư1 34565 vân4 34267 cung2 34216 thich1 34165 cach1 34138 yêu0 34009 nhin2 34007 bon5 33633 qua0 33596
        sông1 33564 ngay0 33507 luc1 33071 giêt1 32931 mơi1 32567 chao2 32303 lăm1 31975 quan0 31729 đưa0 31285
        goi5 31253 hêt1 31129 bao3 31040 răng2 30900 hai0 30391 giup1 30181 hiêu3 30092 lây1 29982 ngai2 29799 ăn0 29738
        tư5 29391 lân2 29254 chinh1 28967 tay0 28344 bo3 28285 cuôc5 28284 nhân0 27894 mât1 27415 ha3 27298 vu5 27106
        năm0 27049 nhân5 26561 xe0 26531 ngươi0 26465 cha0 26048 chua1 26045 khoi3 25391 đinh5 25121 nay0 24835
        tiên2 24791 thơi2 24665 nhe1 24343 cơ0 24072 trơ3 23987 be1 23699 đương2 23695 măt5 23630 do0 23443 gai1 23225
        mây1 22992 vâng0 22814 luôn0 22701 lơi2 22687 chi5 22600 gia0 22587 xuông1 22585 nhau0 22524 đô2 22407 sô1 22376
        đông5 22372 ngoai2 22347 toan2 22237 nơi0 22222 bât1 22123 bây0 22120 thưa0 22059 sat1 22036 thưc5 21933
        tưng2 21786 phong2 21740 ke3 21623 thăng2 21565 chăng3 21297 hang2 21226 băng2 21147 chut1 21003 nhơ1 20999
        chu1 20847 chô4 20690 ly1 20628 hoc5 20580 cô1 20379 nhiên0 20357 tuyêt5 20340 chiên1 20301 si4 20289 le4 20200
        đai5 20200 nhanh0 20137 hoi3 20117 quay0 20117 tiêp1 20105 tinh2 19963 đông2 19827 ôn3 19689 cưu1 19616
        ơi0 19526 bên0 19478 vui0 19428 đê2 19327 gian0 19306 tâm0 19297 tra3 19089 bô5 19069 đêu2 19062 may1 18929
        i0 18920 sinh0 18849 vai2 18846 vi5 18743 đanh1 18702 giông1 18678 xay3 18659 nươc1 18654 tôi1 18477 canh3 18306
        chơi0 18245 trai0 18193 giư4 17777 câu0 17642 hanh2 17540 kia0 17524 ko0 17522 kêt1 17318 vô0 17163 hiên5 17018
        bơi3 16993 giơi1 16987 vưa2 16881 tiêng1 16828 bao1 16800 tương3 16558 chơ2 16477 đep5 16381 lo0 16114
        hinh2 16070 đang1 16013 hôm0 15936 viên0 15818 trong5 15738 vân1 15734 binh2 15465 đu3 15309 cam1 15202
        lơn1 15189 sang1 15097 bac1 15006 thân2 14979 sơ5 14875 biêt5 14835 giai3 14763 phu5 14706 lâu0 14701 cô3 14659
        ve3 14606 thương2 14570 cưa3 14528 cuôi1 14516 thông0 14514 ro4 14457 hơp5 14386 ban3 14362 thương0 14316
        dung2 14272 băn1 14218 đôi5 14060 câu2 14028 trung0 14016 hôi5 13990 ôi0 13962 tra0 13945 chay5 13879 đưa1 13752
        ba0 13721 xac1 13656 ngu3 13653 trơi2 13612 đơi2 13610 tiên0 13567 thân0 13566 thêm0 13524 thay0 13470
        đôi3 13463 mang0 13421 nho3 13408 quân0 13395 nghia4 13136 tôi5 13120 liên0 13067 điên5 13028 du2 12945
        nư4 12842 an0 12812 vê5 12811 phat1 12759 đôi1 12721 bay0 12669 tre3 12648 gân2 12628 hoan2 12555 bênh5 12545
        trương2 12478 đêm0 12447 đơi5 12344 nhi3 12302 tinh1 12236 đât1 12232 đưng1 12215 chiêc1 12100 ngôi2 12066
        trông0 11846 chưng1 11725 kê3 11713 kho1 11699 quyêt1 11681 anh3 11642 xa0 11618 coi0 11613 chiu5 11514
        tâp5 11477 sung1 11437 vong5 11390 năng0 11241 gia1 11200 đan2 11164 tư3 11149 hoăc5 11145 săp1 11132 săn4 11118
        kiêm3 11084 mơ3 11056 dưng2 11021 chuyên3 10954 uông1 10946 xong0 10928 đinh2 10884 dươi1 10875 chon5 10852
        it1 10850 chu3 10825 cao0 10808 vât5 10783 thư3 10746 kiêm1 10734 thông1 10718 măt1 10632 điên0 10610 kê1 10608
        phân2 10604 trương3 10583 biên1 10540 long2 10480 loai5 10356 manh5 10334 đâu1 10264 thuôc1 10242 sư0 10220
        thưc1 10188 dê4 10006 dung5 9989 trai1 9975 vơ5 9974 phia1 9949 quai1 9922 tiên1 9910 điêm3 9894 lưc5 9833
        tê5 9819 chăn1 9801 y0 9784 qua3 9760 khôn1 9740 đau0 9717 sang2 9701 ga4 9690 phut1 9629 sai0 9627 mưng2 9605
        ky2 9550 quên0 9486 minh0 9434 hơi0 9320 tuân2 9308 a0 9303 thu3 9255 chân0 9242 đăc5 9230 kinh0 9177 tri1 9173
        sưc1 9104 mua0 9076 tau2 9076 tro2 9035 quyên2 9025 kia2 9019 quy1 9014 may0 9000 duy0 8994 ha5 8953 môi4 8929
        buôi3 8925 phô1 8915 diên4 8867 bai2 8844 đăt5 8822 phep1 8791 thang1 8759 tai2 8736 nôi3 8728 phap1 8710
        thư0 8677 vu4 8676 hiêu5 8672 khach1 8664 măc5 8652 quôc1 8621 hôn0 8614 mai0 8601 to0 8593 the0 8588 mau1 8533
        đôi0 8527 khiên1 8504 khi1 8494 pha1 8488 tuc5 8479 hê5 8463 yên0 8462 thu1 8424 tuôi3 8403 chuân3 8385
        hoang2 8369 tao5 8359 dân4 8358 đơn0 8346 phuc5 8333 luât5 8301 ca1 8273 dân0 8255 hiêm3 8134 nhiêu0 8072
        sach1 8071 ban2 8040 mau0 8038 cho1 8030 đô5 8030 mang5 7995 chuc1 7956 nhiêm5 7888 pham5 7887 thuc1 7861
        tranh1 7847 thoai5 7835 tiêu0 7802 ư0 7792 thăng1 7776 xâu1 7705 tinh0 7688 gây0 7687 ông3 7667 khu0 7666
        danh0 7665 xuât1 7659 tranh0 7642 ao1 7640 cây0 7606 chi1 7600 mât5 7565 tiêt5 7529 câp1 7503 sêp1 7499
        gia3 7476 xư3 7457 tân1 7447 hy0 7429 liêu5 7391 kha1 7386 tương5 7356 đia5 7353 lac5 7352 thiêt1 7352
        thoat1 7314 ban1 7275 trinh2 7269 đoan1 7223 tam5 7215 mơi2 7148 lênh5 7135 giao1 7134 chang2 7133 dư5 7129
        rơi2 7126 hưa1 7077 ngon0 7048 thiên0 7041 sơm1 7025 năm2 7022 thanh0 6977 dich5 6960 viêt1 6960 dôi1 6936
        hoach5 6935 vơi2 6909 khoe3 6810 giưa4 6800 bong1 6771 nghi3 6754 sư3 6749 hô5 6732 nan5 6699 dây5 6687 ma0 6685
        hai5 6674 hô2 6653 muc5 6625 gioi3 6622 hương1 6585 căn0 6577 tim0 6573 nguy0 6569 viên5 6568 tinh4 6558
        đưc1 6537 tê1 6526 băng0 6516 đoc5 6515 thuât5 6514 phim0 6510 kiêu3 6495 phan3 6495 nhoc1 6474 tri5 6452
        cươi2 6449 bươc1 6445 trôn1 6439 dâu1 6430 rôi1 6430 rươu5 6428 đa1 6423 tu2 6418 canh1 6370 tông3 6369
        vong2 6356 giao0 6351 lâp5 6347 my4 6315 la5 6308 đong1 6293 hoa1 6286 ngu0 6275 tư0 6229 tac1 6208 hoa0 6205
        tui5 6196 thân5 6168 hê2 6166 ngôc1 6166 ban0 6153 lương5 6152 banh1 6145 cang2 6143 bi1 6066 an1 6065 tưc1 6053
        gia2 6038 đam1 6038 di0 6025 da0 6006 lu4 6004 nghiêp5 5997 tham0 5971 thuyên2 5964 ne2 5946 văn0 5938 đôc5 5935
        mong0 5925 gưi3 5916 hanh5 5906 trang0 5893 đua2 5893 hôi2 5891 hen5 5872 nhay3 5864 khoa1 5818 trư2 5812
        khoang3 5805 giac1 5790 cao1 5786 kha3 5779 thây2 5720 đây2 5711 mon1 5702 nghiêm5 5676 cân3 5652 suôt1 5610
        khoan0 5600 phi0 5575 keo1 5570 thât1 5561 chông2 5538 nhât5 5534 suy0 5514 đông0 5504 thi5 5495 tiêc1 5490
        danh2 5485 khung3 5481 mai4 5481 bưa4 5473 trân5 5470 vua0 5461 lai1 5435 đô0 5433 cha3 5431 nghi0 5420
        kiêp1 5416 bưc1 5413 nang2 5400 triêu5 5390 mau2 5369 buôn2 5366 tương0 5356 đơ4 5337 biên3 5334 dai2 5329
        im0 5309 quanh0 5300 toa2 5286 riêng0 5250 huy3 5247 ngơ2 5247 đao5 5231 nô3 5213 sơ0 5203 chưc1 5167
        thăng3 5157 chât1 5147 chông1 5137 đem0 5129 tô3 5126 găng1 5120 linh0 5117 măn1 5105 hoat5 5103 lich5 5103
        thu2 5098 linh1 5086 chưng2 5074 đuôi3 5069 câm2 5064 thuôc5 5049 mơ0 5043 lưa3 5040 ghet1 5002 quen0 4986
        day5 4960 nguyên0 4949 kiên1 4935 tha3 4917 thiêu1 4900 lơi5 4885 căt1 4870 lăng1 4846 thâm5 4841 ngăn0 4835
        sơ3 4831 nhâp5 4817 trach1 4816 lao4 4806 thu0 4804 ngôi0 4797 hăn3 4780 ngưa5 4780 nam0 4773 chia0 4770
        vang2 4750 dây0 4749 cươi1 4735 nghi5 4713 cu4 4705 ghi0 4697 đen0 4692 ly0 4669 đan5 4669 âm0 4668 ngoai5 4655
        binh0 4651 truyên2 4645 trơ5 4643 ki2 4634 tiêc5 4598 dam1 4590 phân0 4590 ta1 4587 phương0 4586 ky1 4585
        vêt1 4573 tây0 4572 đam3 4572 nhăc1 4567 tai0 4559 môi1 4557 quân2 4551 châp1 4535 phiên2 4532 lưa5 4504
        nghiêm0 4503 đô3 4476 la0 4471 rang2 4447 chê1 4444 quy3 4442 ươc1 4439 nưa3 4434 lâm2 4432 nhơ2 4375 bai5 4374
        cươp1 4370 chung0 4355 hat1 4345 đăng2 4337 chi0 4313 tiêu3 4313 hi0 4308 cư3 4272 huy0 4266 ma4 4240
        chuyên1 4231 thai1 4189 lôi1 4188 lê4 4170 ca0 4167 vươt5 4165 cưng0 4164 vung2 4161 phuc1 4149 thuyêt1 4144
        thi0 4142 khăn0 4138 nong1 4138 nhac5 4132 giây1 4100 lai0 4089 tich1 4079 tân5 4078 tha0 4064 răc1 4044
        đoan2 4026 buôc5 4021 thit5 4019 tiêt1 4018 kich1 4010 xet1 3997 toc1 3984 phu2 3972 thuân5 3967 thoa3 3962
        trăng1 3960 u0 3957 tương1 3943 hoa2 3938 lanh5 3917 cưc5 3914 nhom1 3913 cuôn1 3907 tinh3 3895 thương5 3870
        rơi0 3853 chăm0 3844 công5 3841 mai1 3830 giân5 3816 kim0 3808 băc1 3804 soat1 3799 thuy3 3784 miêng5 3777
        san3 3764 dư4 3763 ty0 3756 ưng1 3752 cung0 3749 săn0 3744 lê5 3740 phi1 3736 trôm5 3727 sưa3 3726 lưa2 3709
        tăng0 3695 ca2 3689 vi0 3683 tui1 3681 mưc1 3676 đo3 3672 thanh1 3651 hương3 3643 yêu1 3640 doi4 3638 trai5 3612
        ich1 3611 giây0 3584 thơ3 3558 ti1 3548 diên5 3542 hâu2 3515 biêu3 3512 hôn2 3511 tin1 3501 cơn0 3498 khai0 3498
        nôi4 3498 sâu0 3497 phu3 3496 đao3 3496 vương0 3495 xuc1 3485 ac1 3476 loan5 3476 hâu5 3470 tâm1 3465 năng5 3445
        di4 3437 lơp1 3437 bân5 3433 kinh1 3428 li1 3410 phong1 3410 hung2 3406 lanh4 3400 soc1 3397 chưa4 3395
        rut1 3392 đôt5 3391 a1 3388 canh5 3388 bom0 3385 ky4 3378 lô5 3376 chuyên0 3372 khi3 3370 huynh0 3363 thê2 3362
        luyên5 3361 chương0 3358 đoan5 3353 khâu3 3337 gian3 3333 ơ3 3332 mui2 3322 sach5 3307 đon1 3295 tôi2 3294
        sang0 3292 xêp1 3290 anh1 3288 quan1 3278 la1 3272 ngac5 3262 thăm0 3262 chim0 3245 giâu1 3241 nha0 3240
        lanh2 3239 tương2 3231 quan3 3228 loai2 3225 hong3 3221 vưc5 3206 phong0 3203 tâm2 3200 nao4 3178 thuê0 3170
        hôp5 3169 tôn0 3157 ngưng2 3156 thưa2 3143 tăt1 3136 don5 3135 ê0 3135 tăm1 3134 ân1 3131 nôi5 3124 nhăn1 3123
        dưng5 3115 xanh0 3106 nguyên5 3101 diêt5 3095 siêu0 3083 lăng5 3082 mua2 3075 nơ5 3075 đâp5 3061 măc1 3054
        ô0 3052 sân0 3043 han5 3041 cha2 3036 trưc5 3036 tâng2 3035 kiên5 3033 uy1 3030 qua2 3025 sot1 3022 muôn5 3019
        bac5 3018 đai2 3015 khăp1 3006 đông1 2989 hut1 2971 chăn5 2968 giương2 2962 giam1 2961 lưu0 2957 can0 2956
        say0 2955 doa5 2931 nui1 2928 hao3 2924 năm1 2919 đich1 2916 cuc5 2911 cham5 2902 trân1 2894 xinh0 2869
        tôn2 2868 nguôn2 2866 hưu4 2863 in0 2856 chup5 2855 du0 2852 tan2 2846 dinh1 2837 đoi1 2831 nem1 2821 tơ2 2815
        chia2 2812 phê0 2811 khoa0 2809 khoc1 2809 so0 2807 thua0 2798 truy0 2798 nhâm2 2795 giâc1 2793 xây0 2790
        bang0 2782 đây3 2782 ngân0 2781 chăt5 2774 khô3 2765 nuôi0 2764 hiêp5 2762 ân3 2757 đen2 2753 duc5 2745
        rưng2 2743 bôn1 2738 chan1 2737 kêu0 2726 nghê5 2725 ap1 2721 trê4 2720 hao2 2718 mâu4 2706 sô3 2704 phân5 2701
        châm5 2687 no0 2685 luân5 2684 chư4 2680 khăc1 2673 tôc5 2672 chay1 2664 vân5 2663 khơi3 2660 dong2 2658
        thang0 2654 bo2 2644 lưng0 2643 dang2 2635 quy0 2633 ngan2 2632 di5 2628 hô3 2625 biên0 2620 xưng1 2607
        tuc1 2599 mêt5 2594 giam3 2577 nhân4 2576 bâu2 2572 đao2 2569 trai3 2563 trang5 2557 nguc5 2547 hâm2 2545
        ky3 2545 ga2 2533 tôc1 2522 châu0 2519 lô4 2519 chiêu2 2515 tiên5 2515 mê0 2507 ưm2 2501 mênh5 2487 vơ4 2484
        mi0 2482 hoang0 2479 tung0 2477 hoa3 2474 am1 2473 sam0 2469 triên3 2469 tăng5 2457 săc1 2454 thiêt5 2452
        lay5 2429 sau1 2422 dương0 2416 lui2 2412 me0 2412 nghiên0 2412 hai3 2405 cư0 2402 dao0 2397 đê5 2397 chay3 2392
        mui4 2389 tôn3 2387 my0 2386 sa0 2384 tom1 2379 vinh0 2365 da5 2354 to3 2354 kham1 2351 vi4 2347 o0 2344
        hai2 2343 nga0 2343 toan1 2343 bôi5 2336 ninh0 2329 hưng1 2328 hông2 2326 ông1 2326 ngoan0 2322 xung0 2315
        miên4 2311 đôc1 2311 ghê1 2303 vai0 2292 che0 2286 thương3 2286 giong5 2285 ngươc5 2284 mông0 2282 thiêu5 2281
        sông0 2280 khiên3 2275 bi0 2272 niêm2 2271 thâm3 2271 dăm5 2266 chôi1 2260 kich5 2258 ha0 2256 bung5 2249
        lương0 2249 khoan3 2237 tan1 2237 phan1 2236 rông5 2232 san5 2225 gio1 2223 be2 2213 đôt1 2210 mô5 2200
        đich5 2199 tuy2 2196 thoai3 2194 nhe5 2193 hâp1 2191 hop5 2187 nôi1 2184 thơ2 2184 chiêm1 2181 di2 2179
        chuôt5 2171 câp5 2169 căp1 2168 phâm3 2161 ve4 2156 lôi0 2153 giam0 2152 ghê0 2138 e0 2137 tap5 2128 on0 2127
        kho0 2120 can3 2119 hat5 2116 hai4 2111 đâm0 2107 man2 2094 nghê2 2094 tru5 2089 bao5 2085 đeo0 2080 căp5 2079
        khiêp1 2079 thi1 2076 phu0 2067 tham1 2067 trông1 2067 vơ1 2067 trao0 2065 lao0 2058 thiên5 2057 cu5 2053
        cơ2 2049 cưng1 2048 răng0 2048 thơ5 2046 đê1 2046 tham3 2041 xuyên0 2030 canh0 2029 meo2 2024 điêp5 2017
        phat5 2014 xương0 2014 tô1 2008 ho2 2007 ket5 2005 lan0 2001 cu1 1997 ngưc5 1997 rông2 1990 rô2 1989 vo4 1987
        luc5 1982 tan0 1981 dang5 1980 trăm0 1979 môn0 1977 um0 1974 long0 1967 trung2 1966 ben0 1962 đua0 1961 xa4 1955
        ba3 1947 xưa0 1936 rưa3 1932 giay2 1930 song1 1927 giau2 1925 đe0 1925 lang4 1920 trân2 1920 khuyên0 1919
        hư0 1918 khư1 1918 the3 1916 bai4 1913 công3 1908 coc1 1907 tăc1 1903 ngon5 1901 lân4 1897 bân3 1895 bam1 1887
        cai4 1881 me4 1881 treo0 1881 cân0 1879 gâp1 1879 leo0 1879 đôn2 1875 cân5 1874 đung5 1868 nhiêt5 1862
        tông1 1860 pho1 1859 câm0 1858 tai3 1855 lang0 1851 đoi2 1850 bơi0 1848 trưa0 1848 dân2 1843 hôi1 1838 sư1 1837
        thai0 1837 lơ4 1835 cơ4 1831 hung0 1829 bât5 1828 ep1 1824 đưng5 1823 thâp1 1822 kip5 1817 mach5 1816 đat5 1816
        manh3 1806 đap1 1806 chiêu1 1804 ngon1 1801 âm1 1801 nhiêm4 1799 cơi3 1791 lui0 1790 rac1 1788 cât1 1785
        khân3 1785 nhăm1 1784 môm2 1783 tươc1 1773 vân3 1769 du5 1762 châm1 1757 don0 1753 xâm0 1753 tuy1 1750 đâu5 1740
        dung4 1736 bơ2 1729 nga4 1728 phiêu1 1728 bia0 1727 tuy0 1727 nat1 1726 ao3 1723 dung0 1719 linh4 1714 hoa5 1712
        mươi2 1711 ki1 1706 tom0 1705 thơ0 1700 mưu0 1698 tra2 1697 ve1 1695 xu0 1686 them2 1681 dao5 1680 lat1 1680
        liêu2 1669 ngang0 1669 bêp1 1667 gan0 1665 chai0 1664 căng0 1658 trung1 1654 đêm1 1651 đăng0 1648 man0 1647
        dep5 1645 niêm5 1644 xoa1 1640 chôn0 1637 đeo1 1635 goc1 1634 chinh3 1631 giang1 1627 lang2 1626 đương0 1626
        dưa5 1625 phưc1 1624 miêng1 1623 hô4 1620 bay3 1619 doanh0 1612 thao3 1604 mưa0 1603 đa0 1596 ngơi0 1595
        tai1 1595 huân1 1593 hoai5 1592 sy4 1591 gac1 1588 chưa1 1580 dâu2 1579 ngăn1 1577 thach1 1570 nô0 1568
        câm1 1559 nâu1 1558 thăng0 1557 trăng0 1553 nay4 1552 mô0 1551 đinh3 1549 chơ1 1544 dưt1 1542 săt1 1541
        nông0 1540 mu2 1538 hoang3 1530 lôn5 1528 se3 1526 bây4 1525 mao5 1525 nâng0 1525 điêm1 1524 gương0 1517
        lươt5 1511 ngai5 1510 thôi3 1507 hân0 1504 tu0 1499 kê5 1498 ung3 1491 thâp5 1489 côc1 1485 tuyên0 1485
        thung2 1481 trưng1 1476 tuyêt1 1474 cai3 1466 phâu4 1462 không3 1457 mat1 1457 ôm0 1456 buôn0 1454 dâm0 1453
        mu5 1450 tram5 1450 môi0 1445 bang3 1443 lung2 1443 ngot5 1438 gâu1 1435 căn1 1433 ta3 1430 phiên0 1427
        đâm1 1419 ho0 1418 dương2 1417 gianh2 1417 gi0 1416 bê5 1414 răn1 1406 gian4 1401 moc1 1400 bao2 1389
        khiêu0 1389 quang0 1382 vi1 1381 quang3 1380 ưc1 1378 bao4 1374 quyên3 1369 vơ2 1365 ghe1 1364 liên2 1363
        mươn5 1363 song0 1361 het1 1357 tach1 1354 huyêt1 1352 chong1 1349 lô2 1347 đơn1 1347 sơn0 1346 ngư4 1341
        hang5 1338 kin1 1337 chơ3 1332 phao1 1331 khat1 1327 nhuc5 1320 mông5 1318 phong3 1318 nguyên2 1317 hon2 1316
        hân5 1316 niên0 1314 mu4 1313 suyt1 1313 tuyên1 1313 tôn1 1311 lông0 1309 cơm1 1307 cut1 1303 gian1 1300
        ki4 1298 ga0 1296 he2 1295 ung0 1293 miên2 1292 ta5 1292 ha2 1291 cam0 1288 bô2 1287 soi1 1287 cưt1 1285
        găn1 1285 san2 1285 hen2 1283 muôi5 1283 ray0 1278 chim2 1274 vai4 1273 tao1 1272 nên2 1263 tri2 1263 tu3 1258
        lươi4 1255 bay2 1253 tra1 1251 keo5 1248 gay4 1245 vôi5 1243 liêt5 1238 trươt5 1238 quê0 1234 sưa4 1234 co3 1233
        kiên0 1232 oc1 1231 be0 1226 ba1 1222 buông0 1222 nghiên5 1221 bông0 1218 thai3 1218 kem0 1217 hiên1 1216
        điêu5 1215 mo2 1214 vân0 1214 bui5 1212 cat1 1206 hương0 1203 lô0 1200 khuôn0 1196 khang1 1189 cương0 1187
        ngâm2 1187 nương1 1186 tri0 1186 trưng2 1186 khung2 1185 phe0 1181 xư1 1179 thao1 1177 bop1 1176 khôn0 1176
        khôi1 1173 mi2 1170 thô3 1169 tiêm5 1167 goi1 1165 gôc1 1165 vây0 1163 mô2 1160 môi2 1159 trôi0 1158 man5 1156
        lâu2 1155 manh0 1155 uy3 1155 đang3 1153 đân2 1153 mâp5 1148 sôt1 1148 nhôt1 1146 dơ3 1144 bôi2 1143 ty3 1142
        moi3 1139 dâu0 1138 mên1 1138 giai0 1137 tuân0 1136 xoay0 1134 bong3 1133 choc5 1133 thap1 1133 tam1 1130
        đuôi0 1128 re0 1127 ân0 1126 go0 1125 nhat1 1124 thinh3 1120 âu0 1119 gơi3 1118 nham3 1117 chin1 1114 ki3 1112
        pha0 1111 hôi0 1108 ngăm1 1105 khô0 1099 phai1 1095 tươi0 1094 nut1 1092 tơm3 1092 ti3 1089 bôc1 1088 hôn4 1085
        hô0 1084 thoang3 1084 triêu2 1084 ngôn0 1083 ru4 1082 mac5 1081 đên2 1081 đuôi1 1080 xich1 1079 đit1 1079
        li0 1074 ngu4 1074 by0 1072 tang0 1069 can5 1066 vưt1 1066 xa5 1066 tron2 1065 truyên5 1059 tiêm0 1056 do2 1055
        vinh4 1053 đap5 1053 giơn4 1052 cươc5 1049 nu5 1043 ruôt5 1035 thiêp1 1032 hit1 1030 nương0 1030 troi1 1030
        đia4 1030 giât5 1028 gơi5 1026 kem1 1026 chăng0 1023 vây2 1023 ôm1 1023 thu5 1021 lâm0 1020 xom1 1020 tich5 1019
        lo2 1018 vay1 1016 giơ0 1015 côt5 1013 thôi1 1012 vươn2 1012 tu5 1011 hiêp1 1010 heo0 1009 chung3 1008 he0 1008
        van0 1007 ma1 1006 hoan0 1005 đang2 1005 dang1 1004 man4 1003 thiêu0 1003 vo3 1000 met1 995 huông1 994 han2 993
        bư5 989 gô4 988 na5 987 đôi2 987 bau1 984 gơ4 983 chuông0 982 bôi1 981 mêm2 979 quy2 974 quy4 974 cai0 973
        lăn5 973 giap1 971 ưu0 970 ngoc5 969 quyên1 968 hang0 966 mo3 966 tung2 963 diêu5 960 đe3 960 san0 959 viên4 959
        cuông2 956 cu0 955 da4 952 hiêm1 950 re4 949 tang2 947 ghen0 946 bưc5 941 tia0 941 tran2 941 vôn1 941 quet1 940
        cô4 939 nhip5 939 beo1 938 bô3 936 cui1 935 thiêp5 935 tân0 935 khoac1 934 điên3 934 phôi3 928 truc5 922
        than0 921 vưng4 921 huyên2 920 thao0 918 kiêt5 911 tho3 910 trum2 910 khich1 909 gôi1 908 ngơ1 908 lơn5 903
        dương4 902 sơi5 902 bach5 901 thăc1 900 ngân3 899 tô0 898 trinh0 896 bơt1 895 nôp5 891 chân1 888 ngưi3 887
        căm1 881 chiêu0 876 khoi1 874 sương1 873 đinh0 873 gop1 872 loat5 871 nghin2 871 dum2 870 re3 869 đon2 867
        lot1 864 guc5 863 gôm2 862 ngheo2 861 bê0 860 rôt1 860 xăng0 859 cơm0 858 ganh1 857 gat5 853 xe1 853 co0 852
        đăn1 850 ti0 847 hoai2 846 ươt1 845 ôn2 844 va3 842 ve0 840 ong0 838 suât1 838 cang3 837 cuôn5 837 nhi0 835
        chui0 833 viêt5 833 bâc5 831 ngương4 828 tha2 828 bên1 827 toa3 827 lăp5 825 phân1 823 lau0 820 râu0 819 xi2 816
        to2 815 ưa0 814 khoanh3 813 thô0 809 tuyên3 808 len1 807 biên5 806 trât5 806 bê2 805 xuân0 805 đam2 804
        khơp1 802 tru1 802 ngưng0 801 sup5 799 day2 797 năng1 792 cây5 791 ai1 787 boc5 787 thuê1 786 đê0 786 nhi1 785
        buyt1 784 nhang2 784 trương0 784 vơ3 784 chôt1 783 thăt1 781 nhăt5 780 phât5 780 giang0 778 băp1 776 sôc1 775
        chơ5 773 moc5 773 truc1 773 khoang0 772 lươc5 772 sung0 772 bo1 770 cư5 770 bo5 767 nôn0 765 ngao2 764 rao2 762
        hoan5 761 ngoai1 760 tam0 759 van1 759 nganh2 756 quân5 756 bôn2 755 hâm0 751 thiu3 750 mô3 749 phôi1 748
        chep1 746 lươi1 744 dan0 743 dăt1 741 va0 741 hêt5 740 hươc1 739 khuc1 739 nhet1 739 cia0 737 cut5 737 ngăt1 736
        thac1 735 dư0 734 trư4 734 giăt5 733 đao1 732 rua3 731 but1 730 công1 730 chu0 728 gây5 728 mươi0 727 thach5 727
        đưt1 727 tâu2 726 mơ1 725 nhân1 724 vong0 723 chen1 722 hiên2 722 mong1 722 de0 721 đac5 721 bê3 719 ghep1 718
        ky5 718 cai2 717 nap5 717 thuân2 717 rôn5 716 xi1 715 cương4 713 kênh0 713 nha1 712 vang0 711 choc1 709 cưu5 709
        xông0 709 nhay5 706 sơ2 706 xai2 705 xô0 704 chăn0 702 voi0 702 đo0 701 cương2 700 nô4 700 văng1 700 cao5 699
        day4 699 rông4 699 dan2 697 tang3 697 đôn5 696 mơ2 694 câu1 692 lât5 692 ngâp5 690 dai5 688 hưu0 684 kê0 684
        trang1 684 nôt1 682 đăt1 681 gon5 680 đoat5 677 lông2 675 quây1 675 khâu1 674 hiên3 672 hăc1 672 khen0 672
        côn0 671 xê1 671 đêch5 669 go4 668 dươc5 666 cưu2 664 hoan4 664 khoai1 663 pin0 663 đai4 662 ranh3 661 chem1 660
        khoai0 660 no5 660 long3 659 xiu1 659 bây2 656 co2 656 nho0 656 van5 655 chuôc5 654 dô4 654 đêch1 653 nuôt1 650
        te1 648 lăn0 647 bu2 646 mây0 645 ngô5 643 viêm0 642 doc5 639 lê0 639 mưc5 638 tê3 638 run0 637 ơ0 637 nhu0 631
        xa2 631 be3 630 lap5 629 su0 627 xương3 625 cươi4 623 hô1 623 hăng2 622 đa2 620 ranh0 617 đai0 617 nhâc1 616
        thoi1 616 hong5 613 trưng0 613 ham5 611 rươi4 611 tây3 609 mai5 608 rung0 608 suc1 608 trich1 607 văt5 605
        vit5 600 lăng0 599 dip5 598 tat1 598 gium2 597 muôi1 596 đô4 596 ôi1 595 châm0 594 giang3 592 trôn5 592
        tiêm2 591 ba4 589 bôt5 588 rơt1 588 phu1 587 le3 585 tiên4 585 trân0 585 kiêm5 584 nhên5 584 cup1 583 lăc1 583
        chăm2 582 vât1 582 gai2 581 lăp1 581 muôn0 580 xăm0 580 phun0 579 tông0 579 hơ3 578 lêu2 578 non0 577 đây5 577
        non1 576 rươi3 576 thâm2 576 đăng3 576 chiên0 575 seo5 575 tan3 575 gay0 574 khoa3 574 lôt5 573 tăm0 573
        thâm0 572 tân2 572 xa1 572 tât5 569 đay1 569 hang4 568 ri3 568 mua1 567 nha4 567 tao2 567 thơm0 567 qui1 566
        xôn5 566 điêu1 565 chuy0 564 rui3 564 ti5 564 chuôn2 561 lo5 561 lun2 561 dâp5 560 ket1 559 tê0 558 mu0 557
        râp5 557 đe2 557 kiêu0 556 ken2 555 set1 555 luân0 554 buông2 553 gơm1 553 gươm0 553 diu5 552 dâng0 550
        chơp1 548 bâm1 547 chuyên2 546 khao3 545 ngâm5 545 lây0 543 trông2 542 ham2 539 yêm3 538 treo2 537 nhăm2 536
        banh0 535 bua2 535 chay2 535 thiêng0 535 dơ0 533 sanh1 531 lô1 530 nhơ3 530 lan2 529 cong2 528 phô3 527
        ngâu4 525 thep1 525 tư1 525 chua0 524 nêm1 522 trâm2 521 ui3 521 tui0 520 chuôi4 519 côt1 519 dê0 519 đêt5 519
        chuông2 518 vay0 518 vinh5 517 lung4 516 quang4 515 so5 515 vô4 515 đinh1 515 bich5 513 nhi5 512 suyt5 512
        vai3 512 dan1 510 thung0 509 lơ2 508 sưu0 508 khinh0 507 chia4 506 ngư0 504 vach5 504 phiêu0 502 lâp1 501
        khan1 499 na4 499 sanh3 499 uy0 499 đâng1 498 lao1 497 liêu4 497 sươn2 496 quây2 495 khư3 494 căm0 491 ngât1 491
        cu3 490 loc5 490 chinh0 489 cơ1 489 kep5 489 bup1 488 đơt5 487 nhương2 486 rap5 486 ham0 485 khao0 483
        thiêu3 483 khăng3 482 lươn5 482 vu1 482 bat1 481 mia0 481 rê3 481 bang2 480 bơ0 479 nan2 479 điên2 479 hanh4 478
        lân5 478 diêp5 477 ham4 477 nghich5 477 xa3 477 đô1 477 tăc5 476 câu3 475 dôi5 475 săm1 474 nhô3 473 khôi0 472
        ro0 472 xin3 471 đi4 470 toa5 469 giot5 468 nguy5 468 xach1 466 chô3 465 lung0 465 nâu0 464 te2 463 kem2 462
        đai1 462 quây5 458 rach1 458 toa0 456 moi0 454 ven5 454 thươc1 453 hơi4 452 khiêu1 452 ngây0 452 quăng0 452
        rôi4 452 vuôt1 448 ôc1 448 bây5 447 chân3 446 nhi2 446 sao1 446 nit1 444 nhat5 443 ngô0 441 êm0 441 tro0 440
        lanh1 439 nâm1 439 song2 439 thinh5 439 cheo2 438 mang2 438 tâu3 437 khơi0 436 bơm0 435 him0 435 nâp1 435
        cây1 434 xui0 434 xưng0 434 xoa0 433 khung0 432 phiên1 432 ren2 431 sâp5 431 ang0 430 mi4 430 đoan0 430 dăn5 429
        duyên0 428 mon2 428 coi4 427 ruôi2 427 côi0 426 khơ2 426 rau0 426 choang2 423 coi2 423 kheo1 423 khuân3 423
        bun2 422 buôm2 422 lân3 422 chôn1 421 khoe0 420 lâu5 420 ngai0 420 quăc5 420 bia5 419 mong3 419 nơ3 419
        phan2 419 thâu1 418 đam0 418 ngôt5 417 han0 416 bung2 414 gen0 413 nao1 413 soi0 413 đâm2 413 căn5 412 tron5 411
        dôn2 410 rang1 410 hư3 408 net1 408 am0 407 phô0 406 sôi0 405 miêu0 404 hep5 403 nguyêt5 403 bua1 402 ây0 401
        ao2 399 lam0 399 manh4 399 ngao5 398 nhuân5 398 son0 398 tung1 398 dơi2 397 ta2 397 cay0 396 gach5 396 lơ0 396
        vô2 395 chuc5 393 me3 393 thung3 393 sup1 389 toi0 389 đao0 389 chun0 388 hông0 388 sương0 388 nghiên2 387
        va4 387 cau1 386 khâu0 386 chi2 385 day0 385 nhan4 384 khai1 383 kiêm2 383 lươt1 383 thuy5 383 xam1 383 gai0 381
        gui4 381 lot5 381 khuât1 380 nghiêt5 380 xuôi0 380 chưi3 379 ki0 379 thê0 379 trêu0 379 can1 378 men0 378
        đe4 377 đua4 377 ư2 377 liu1 375 nay3 375 bươm1 374 hiêu1 374 tim1 374 voi2 374 đăm1 373 huê5 372 nên1 372
        ngâu2 371 soan5 371 sưng2 371 boc1 370 vân2 370 len3 369 tuy3 369 dưa0 367 rưc5 367 không1 366 môc5 366
        nhich1 366 nông2 366 thet1 366 bôi0 365 le5 365 ngơi5 365 bâm3 364 bưu0 364 đan0 364 han4 363 len0 361 nhuc1 361
        bông4 360 dôc1 360 đưc5 360 lê2 359 nhai0 359 bit5 358 ty1 357 na0 354 phung5 354 thăn1 354 bâm2 353 lam5 353
        vac1 352 vu0 352 bum2 350 ngư5 350 khuyên1 348 xot1 348 guy0 347 lêch5 347 giơi2 346 si3 346 tran1 346 ron0 345
        rên0 345 vây4 345 cap1 344 ken0 344 sươi3 344 banh3 343 găng0 343 nat5 343 phê1 343 phơi0 343 tia3 343 tro5 343
        nhao5 341 âm3 341 đui2 341 hai1 340 lương4 340 tuê5 340 nhơ4 339 bê1 338 cua0 338 hut5 338 hông3 338 xơ0 338
        ơt1 338 dinh0 337 lươi2 337 roi0 337 gâm2 336 thây0 336 nưt1 335 phêt1 335 rây2 335 sec1 335 bach1 334 khe0 334
        nhiêu4 334 nô5 334 hu2 333 khiêt1 333 trơn0 333 chôm0 332 manh1 332 nhay1 331 vun5 331 gin2 330 tôm0 330
        đôn0 330 hoanh2 329 lưu5 327 nhung1 327 trăc5 327 van4 327 bong0 326 chươc1 326 miên5 326 nhôi2 326 vương1 326
        giơ3 325 loi4 325 lây4 325 nhưa5 324 phanh0 324 bi2 323 hong2 323 nhanh1 323 sô0 323 triêt1 323 điêc1 323
        thoang1 322 đit5 321 cun1 320 gây2 320 phang0 320 thư5 320 thay3 319 xuân3 319 ôn0 319 bi3 318 mơ5 318 cưa0 317
        mơ4 317 ne1 317 yên1 317 phươc1 316 văn5 316 chanh0 314 chư0 314 chôn2 313 bây1 312 giây2 312 khuya0 312
        neo0 312 đang4 312 chen0 311 liêm1 311 vach1 311 noc1 310 rua2 309 nhương5 308 rot1 308 then0 308 xit5 308
        que0 307 xôi0 307 rơ5 306 bưa2 305 choang1 305 cưu3 305 dơi0 305 khiên0 305 tang5 305 chich1 304 chuôi1 304
        dơ4 304 giêng1 304 ran1 304 đêu3 304 trương5 303 liêng0 302 truông2 302 chât5 301 hem3 301 năp1 301 a5 300
        ha1 300 nê2 300 trao2 300 vat5 300 gao2 299 quyên0 299 thoai1 299 bôn3 298 lam4 298 qua5 298 viêng1 298
        lông5 297 xen0 297 bơi2 295 nhươc5 295 duyêt5 294 lach1 294 nan3 294 ranh2 294 nghiêng0 293 min2 292 phiên5 292
        đăp1 292 bang1 291 choi5 291 chơt5 291 chương3 291 von0 291 ngân2 290 sê0 290 cong0 288 côi1 288 khiêm0 288
        trut1 288 điêm2 288 chang0 287 nhao2 287 tê2 287 hăng0 286 pho0 286 dưng0 285 bông3 284 nghênh0 284 chai3 283
        lin2 283 ngưa1 283 rơ4 283 thuân4 283 dang0 282 han1 282 rô3 282 coc5 281 đa3 281 cung1 280 xao3 280 ao0 279
        chui2 279 chê0 279 hong0 279 huân0 279 ô2 279 nưc5 278 cao2 277 then5 277 ngo1 276 đăc1 276 rai4 275 lây2 274
        ru3 274 bip5 273 lân0 273 lương2 273 rai3 273 tang1 273 kê2 272 nup1 272 rinh2 272 cơi4 271 keo2 271 vui2 271
        cư2 270 kông0 270 goa1 269 khăng0 269 kong0 269 sâm0 269 nhai4 268 ro2 268 vung5 268 xoăn1 268 lua1 267 mâu3 267
        năn0 267 gom0 266 xit1 266 xoay1 266 dai3 265 do1 265 dâm4 265 mia3 264 suôi1 264 tâp1 264 âu1 264 ưng0 264
        gao5 263 lon0 263 căn2 262 mach1 262 nin1 262 ru0 262 siêt1 262 thôn0 262 nôi2 261 quân1 261 ben1 260 bot5 260
        chôi3 260 cui3 260 vet1 260 nhưc1 259 sâm1 259 thưng2 259 nhiêp1 258 trâu0 258 tưa5 258 vanh2 258 deo3 257
        kim2 257 lut1 257 lôp1 257 nai0 257 sua3 257 tua0 257 ngat5 256 nghêch1 256 bo0 255 nen1 255 thăp1 255 đu5 254
        pham2 253 co5 252 keo0 252 chăng5 251 dai0 251 eo0 251 diêm0 249 kheng1 249 tuê1 249 te3 248 dôt1 247 hao1 247
        hon0 247 mep1 247 thăm3 247 cong1 246 xiêc1 246 nham2 245 kai0 244 lang3 244 nhe4 242 bơi1 241 nhin5 241
        cươc1 240 khoan1 240 rach5 240 xin5 240 hach5 239 nhăn0 239 than3 239 tơ0 239 đâm4 239 chôc1 238 hu1 238
        mâu1 238 va1 238 đanh2 238 khan0 237 o1 237 đu0 237 choi1 236 loa0 236 trăc1 236 văng0 236 xi0 236 xăn1 236
        hôt1 235 nguôi5 235 sung2 235 them0 235 chay0 234 lai4 234 sưng0 234 xi3 234 êch1 234 ươp1 234 xeo1 233 băn0 232
        di1 232 đay2 232 nây1 231 ty5 231 canh2 230 dom0 230 nhi4 230 như3 230 phăng3 230 đêm5 230 câm3 229 lu0 229
        măng1 229 nhăn2 229 xeo3 229 môc1 228 up1 228 boong0 227 đôn1 227 hiên0 226 ia2 226 âm2 226 nhâu5 225 vươn0 225
        ương0 225 bu0 224 diêu4 224 gât5 224 lôi5 224 nêu0 224 xo3 224 dương5 223 khoăn0 223 mâu0 223 bia2 222 chot1 222
        quăng3 221 tu1 221 gay1 220 lươm5 220 quang1 220 sâu1 220 lanh0 219 nhon5 219 ri0 219 đâm5 219 ba5 218
        khuyêt1 218 ma5 218 oan1 218 riu2 218 trui5 218 tuy5 218 uc1 218 đuc1 218 gieo0 217 ni3 217 kang0 216 khoat1 216
        ngo4 216 oa0 216 oan0 216 trat1 216 bai1 215 my2 215 thuyên0 215 đuc5 215 hom2 214 lay0 214 nhu3 214 tung5 214
        tuôt5 214 mim3 213 miên0 213 quy5 213 tho5 213 bu1 212 lôc1 212 reo0 212 rê4 212 thâm1 212 đăng1 212 hươu0 211
        kên2 211 loan0 211 queo5 211 rui5 211 nong2 210 trum0 209 got1 208 si0 208 thinh1 208 hoăc1 207 leo4 207
        quât1 207 rương0 207 gio3 206 quân3 206 têt1 206 leo1 205 loc1 205 lua5 205 gôn0 204 hưm2 204 ngưa2 203
        ngương5 203 nhung0 203 tut5 203 đut1 203 kiêng0 202 nau1 202 găt1 201 nom0 201 rung5 201 điêu0 201 eo1 200
        he1 200 lăn2 200 pho2 200 se0 200 biêng1 199 dăn2 199 khep1 199 nhơ0 199 ra4 199 hưng0 198 qui3 198 rưa4 198
        hưc1 197 thâu2 197 côp1 196 mot5 196 bet1 195 mai2 195 nhoc5 195 nhuôm5 195 xe3 195 hi1 194 que2 194 bôc5 193
        cuc1 193 tưng0 193 xây3 193 xươc1 193 dong0 192 khia1 192 lang1 192 diêu2 191 ngu5 191 vuông0 191 văt1 191
        nai5 190 ngoan5 190 ta4 190 phông2 189 rang5 189 ranh4 189 chum2 188 chưa2 188 dia4 188 luông2 188 mut1 188
        ngơ0 188 đung2 188 chuôc1 187 triêt5 187 khoang1 186 ngoi2 186 oi1 186 nê3 185 xao0 185 côn2 184 khôc1 184
        min0 184 rôi0 184 troc5 184 châu5 183 kan0 183 lân1 183 nan0 183 ngui3 183 ngâm0 183 rơn5 183 trang2 183 bô0 182
        ngoan4 182 niêm0 182 rap1 182 xao5 182 gân0 181 ria2 181 trâm4 181 chanh1 180 chao1 180 chong2 180 khiêng0 180
        lăm0 180 coi3 179 cung3 179 dai4 179 dôt5 179 mat5 179 sai2 179 thao5 179 xua0 179 âp1 178 đôm1 178 bon0 177
        choi0 177 măp5 177 xơi0 177 meo5 175 râm5 175 đơi1 175 ưa2 175 bich1 174 sac5 174 nhung4 173 bênh0 172 lim0 172
        ngông4 172 ngăt5 172 quat5 172 rươt5 172 thiên2 172 bên2 171 chua2 171 kip1 171 lia2 171 qui0 171 ngưa3 170
        tat5 170 truy5 170 huyêt5 169 khâm0 169 uôn1 169 chao0 168 gian2 168 lit1 168 phac1 168 quây3 168 suôn0 168
        thui1 168 thê5 168 bôn5 167 chương1 167 khanh1 167 num1 167 soai1 167 bit1 166 nhom4 166 xiu3 165 bat5 164
        cay2 164 cum1 164 khuây1 164 ku0 164 lôc5 164 vơt1 164 xay0 164 nhot1 163 ra2 163 rung2 163 trôi4 163 tum1 163
        tơi0 163 ci1 162 gâp5 162 hot1 162 ngay1 162 quat1 162 thiên1 162 trơ0 162 xao1 162 at1 161 năc5 161 pam0 161
        sang3 161 sanh2 161 sun0 161 khet1 160 nanh0 160 ngâm4 160 quât5 160 teo5 160 ưi0 160 cơt5 159 muôi4 159
        mâm2 159 quê1 159 rem2 159 rây3 159 sut1 159 ceo0 158 chich5 158 ghim0 158 thoi0 158 che4 157 ganh0 157 lua2 157
        mê4 157 mưt1 157 te0 157 cheo1 156 găm0 156 găm5 156 hoi0 156 ki5 156 noc5 156 vo2 156 nôc1 155 tinh5 155
        be4 154 dưa2 154 la3 154 mang3 154 môt1 154 trây2 154 vương5 154 chiêm0 153 le0 153 ria0 153 âu3 153 bai0 152
        chao3 152 ni0 152 phơt1 152 sen0 152 suc5 152 hăm0 151 khiêm1 151 ngâng3 151 nhôn5 151 trôi5 151 văn2 151
        can2 150 giuc5 150 lăng3 150 răm1 150 vung0 150 boi1 149 hên0 149 li2 149 ninh5 149 phông5 149 tit1 149 cap5 148
        chap5 148 châu2 148 dim2 148 pha2 148 phăn1 148 po0 148 gao0 147 nga3 147 rong0 147 thoc5 147 tru0 147 vy0 147
        xeng3 147 xuông2 147 hơi2 146 loanh0 146 đan3 146 che2 145 chom2 145 cum5 145 nghet5 144 sâu2 144 thăn2 144
        bưng2 143 nơi1 143 phim1 142 phân4 142 so2 142 tưu5 142 ut1 142 pan0 141 thim1 141 trong2 141 vung4 141 vêt5 141
        xem1 141 xô3 141 bip1 140 bân2 140 ke2 140 nha3 140 chan0 139 gie3 139 teo0 139 teo2 139 tho0 139 try0 139
        vo0 139 bưa5 138 lam3 138 luy5 138 nhâm1 138 trao1 138 bương1 137 gin0 137 hen0 137 liêu0 137 nhut1 137
        thoc1 137 vâp1 137 xu2 137 đam5 137 chôp5 136 mon0 136 nang0 136 phich5 136 poe0 136 thinh2 136 toai1 136
        tươi1 136 âp5 136 gu0 135 loi2 135 lư4 135 tem0 135 hăn2 134 lêt1 134 mưa3 134 ngan1 134 ui0 134 vot5 134
        điêu3 134 chân2 133 ken1 133 kiêu2 133 loa4 133 mia5 133 mên2 133 phi3 133 bây3 132 gai4 132 hoi1 132 khoe1 132
        nhe0 132 quyêt5 132 toi3 132 bơm5 131 căm2 131 giun0 131 mun5 131 rao0 131 mu3 130 nhen5 130 rang0 130 keo3 129
        khai3 129 meo1 129 mươn1 129 nham0 129 phet1 129 xiên0 129 boa0 128 châp5 128 cui2 128 gôi5 128 nai2 128
        ngum5 128 tac5 128 vây1 128 yêm1 128 bân0 127 hu3 127 mi5 127 tho2 127 vom2 127 vơ0 127 cung5 126 diêm1 126
        dâu4 126 gang2 126 go2 126 lui5 126 lưng3 126 nâc1 126 phai2 126 hem4 125 hun0 125 rô0 125 thuy2 125 xơ3 125
        hum2 124 ke4 124 lung1 124 lut5 124 mon5 124 tanh2 124 đuôc1 124 dom2 123 la4 123 măng0 123 nên5 123 phi2 123
        uê1 123 xươc5 123 bôt1 122 phach1 122 chơp5 121 kha0 121 lưng2 121 phao0 121 rao1 121 râm0 121 tôt5 121
        xiêng2 121 xương1 121 chân5 120 cop5 120 en0 120 ia3 120 nhăng0 120 nôi0 120 panh0 120 đu2 120 bon1 119 cô5 119
        dep1 119 ham1 119 răn5 119 sây1 119 ngô1 118 vang3 118 xay4 118 banh2 117 duê5 117 mân4 117 tre0 117 chiêt1 116
        de3 116 luôn2 116 ngong1 116 ngưu0 116 nhâp1 116 tuôt1 116 chư2 115 giâm4 115 hê0 115 nhoang1 115 đoa1 115
        đoa5 115 bep5 114 chac1 114 de2 114 dân1 114 hăt1 114 ke0 114 lai3 114 mang4 114 mui0 114 nêp1 114 phiêm1 114
        ruông2 114 tâm3 114 tơn5 114 cu2 113 gac5 113 hoan1 113 hơm5 113 loi5 113 lơ3 113 mang1 113 nơ0 113 rây4 113
        thâu0 113 thôn1 113 tâng0 113 tâu0 113 vet5 113 ăt1 113 muông4 112 ngo0 112 nhai3 112 ti2 112 giương0 111
        hao0 111 heo3 111 i1 111 linh2 111 mo1 111 măn5 111 thuc5 111 u1 111 nhap1 110 răn0 110 rơm0 110 trương1 110
        lin0 109 loi3 109 lư0 109 nghen4 109 nung0 109 sap1 109 thuy0 109 ơm2 109 bơ5 108 gio2 108 tuôc5 108 xui1 108
        ge0 107 gien0 107 kinh2 107 ngach1 107 nâng1 107 nêm5 107 roi1 107 roi5 107 thôt1 107 xat1 107 xo1 107 bông2 106
        chip1 106 i4 106 luy4 106 mia1 106 nhê3 106 nu0 106 thoa0 106 cong4 105 ga3 105 gan1 105 gia4 105 huyt1 105
        kêp1 105 lun1 105 pao0 105 ret1 105 rich1 105 tia1 105 tong0 105 trăn0 105 tuân1 105 gan2 104 hinh4 104 hây0 104
        lac1 104 mac1 104 soi3 104 sôi2 104 xao2 104 kinh3 103 lai2 103 lau1 103 luôc5 103 me2 103 như2 103 oi0 103
        phai0 103 toan0 103 tri4 103 giêm1 102 hôc1 102 khuynh0 102 ngang1 102 phung0 102 tong2 102 vang1 102 đo5 102
        giêng2 101 hư1 101 mao0 101 ngo3 101 rong2 101 đăn5 101 cuông1 100 doc1 100 lăt5 100 pai3 100 phinh2 100
        phương5 100 ten0 100 toac5 100 trơn1 100
        """
}
