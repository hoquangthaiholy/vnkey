/// Các âm tiết tiếng Việt thông dụng, xếp đại khái từ hay gặp nhất trở xuống. Dùng để chọn giữa các từ cùng
/// khớp một chuỗi phím thiếu dấu khi chưa có bằng chứng nào từ chính người dùng ("được" thay vì "dược").
/// Đây là danh sách soạn tay, không phải thống kê từ một kho ngữ liệu: chỉ cần đúng ở mức "thông dụng hơn hẳn".
enum CommonWords {
    static let list: [String] = """
        và của là có không được cho trong người một những đã với các này để khi ở về như tôi đến ra thì nhưng
        cũng lại sẽ đó nhiều mình anh em bạn ông bà chị con nó họ chúng ta rất phải còn hơn nào gì ai đâu sao
        thế vậy nếu vì nên mà hay hoặc rồi đang vẫn chỉ nữa thôi lên xuống vào trên dưới trước sau giữa ngoài
        năm tháng ngày giờ hôm nay mai qua tuần lúc lần đầu cuối mới cũ lớn nhỏ cao thấp dài ngắn tốt xấu đẹp
        nhà nước việc làm học sinh trường lớp thầy cô sách báo tiền hàng bán mua giá công ty việt nam hà nội
        thành phố quốc gia dân tộc xã hội kinh tế văn hóa chính phủ phát triển thế giới thời gian đời sống
        biết nghĩ nói nghe thấy nhìn đi đứng ngồi nằm ăn uống ngủ chơi chạy viết đọc hỏi trả lời giúp cần muốn
        thích yêu thương nhớ quên tin hiểu tìm gặp gọi đưa lấy mang giữ bỏ mở đóng bắt thử dùng thêm bớt
        đúng sai thật giả khó dễ nhanh chậm sớm muộn gần xa đủ thiếu khác giống chung riêng mọi từng cả hai ba
        bốn sáu bảy tám chín mười trăm nghìn triệu số tên tuổi chuyện điều cách phần loại mặt tay chân mắt
        đường xe máy điện thoại tính mạng trang web thông báo gửi nhận thư tin nhắn hình ảnh âm nhạc phim
        cảm ơn xin chào tạm biệt vui buồn khỏe mệt đau ốm bệnh thuốc bác sĩ viện cơm phở cà phê trà bia rượu
        trời đất mưa nắng gió biển sông núi rừng cây hoa lá chim cá chó mèo màu đỏ xanh vàng trắng đen
        tiếng lời câu chữ bài ý nghĩa vấn đề kết quả nguyên nhân lý do mục đích kế hoạch chương trình dự án
        khách bạn bè gia đình bố mẹ vợ chồng cháu trẻ già nam nữ trai gái đội nhóm tổ chức họp
        luôn thường đôi ít hầu hết toàn bộ hoàn chắc chắn tất nhiên có lẽ thực sự đặc biệt quan trọng
        bây lâu vừa sắp từ tới tận theo bằng do bởi tại nhờ cùng nhau lẫn riêng tự chính ngay liền
        """.split(whereSeparator: { $0 == " " || $0.isNewline }).map(String.init)

    /// Từ -> trọng số (từ đứng đầu danh sách nặng nhất). Từ không có trong danh sách: 0.
    static let weight: [String: Int] = {
        var out: [String: Int] = [:]
        for (i, w) in list.enumerated() where out[w] == nil { out[w] = max(40, 600 - i) }
        return out
    }()
}
