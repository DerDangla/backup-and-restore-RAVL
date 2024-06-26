resource "aws_instance" "myinstance" {
  ami                    = data.aws_ami.amazon_linux.image_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.allow_tls.id]

  tags = {
    Name = "Emander-Instance"
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = var.my_public_key
}

